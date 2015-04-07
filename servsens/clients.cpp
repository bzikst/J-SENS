////////////////////////////////////////////
// Clients example module for J-SENS protocol
// See https://github.com/bzikst/J-SENS for details

#include <fstream>
#include <cstring>
#include <algorithm>

#include "clients.hpp"
// some internal dependencies was here

ClientPool Clients; ///< pool holds client data

std::string do_get_status(const JSON_Node * node, const JSON_Node * params);
std::string do_start(const JSON_Node * node, const JSON_Node * params);
std::string do_stop(const JSON_Node * node, const JSON_Node * params);
std::string do_get_values(const JSON_Node * node, const JSON_Node * params);
std::string do_set_ports_setting(const JSON_Node * node, const JSON_Node * params);
std::string do_restore(const JSON_Node * node, const JSON_Node * params);
std::string do_update(const JSON_Node * node, const JSON_Node * params);
std::string do_get_info(const JSON_Node * node, const JSON_Node * params);


////////////////////////////////////////////////////////////////////////////////
// Client::process() - parse command buffer

void Client::process()
{
 respond.clear();
 respond.first_line = u8"HTTP/1.0 200 OK";

 if(!request.body.size())
   {
    respond.body = u8"{\"status\": {\"code\":\"clientError\", \"message\": \"Request is empty.\"}, \"data\": null }";
    return;
   };

  HttpInfo::Headers::iterator it;

 // check validity
 if((it = request.headers.find("content-type")) == end(request.headers))
   {
    respond.body = u8"{\n \"status\":\n\t{\n\t \"code\":\"clientError\", \n\t \"message\": \"'Content-Type' header not found.\"\n\t},\n \"data\": null\n}";
    return;
   };

 if(it->second.find("application/json") == std::string::npos)
   {
    respond.body = u8"{\n \"status\":\n\t{\n\t \"code\":\"clientError\", \n\t \"message\": \"'Content-Type' must contain 'application/json'.\"\n\t},\n \"data\": null\n}";
    return;
   }

 JSON_Node json;

 if(!(json = parse_json(request.body)).is_valid())
   {
    respond.body = u8"{\n \"status\":\n\t{\n\t \"code\":\"serverError\", \n\t \"message\": \"Parse error.\"\n\t},\n \"data\": null\n}";
    return;
   };

 if(json.is_object())
   {
    const JSON_Node * node;
    std::string (*hook)(const JSON_Node * node, const JSON_Node * params) = nullptr;

    if((node = json.by_name("cmd")) && (node->is_string()))
      {
       const std::string & val_name = node->value;

       if(val_name == "get-status")
         hook = do_get_status;
       else if(val_name == "get-info")
         hook = do_get_info;
       else if(!is_valid) // TODO: may be need to check delay here
         {
          respond.body = u8"{\"status\": {\"code\":\"forbidden\", \"message\": \"verification failed.\"}\n";
          return;
         }
       else if(val_name == "start")
         hook = do_start;
       else if(val_name == "stop")
         hook = do_stop;
       else if(val_name == "get-values")
         hook = do_get_values;
       else if(val_name == "set-ports-setting")
         hook = do_set_ports_setting;
       else if(val_name == "restore")
         hook = do_restore;
       else if(val_name == "update")
         hook = do_update;
       else
         {
          respond.body = u8"{\"status\": {\"code\":\"clientError\", \"message\": \"Unknown command.\"}, \"data\": null}";
          return;
         };

       if(hook)
         respond.body = hook(node, json.by_name("params"));
      };
   }
 else
   {
    respond.body = u8"{\"status\": {\"code\":\"clientError\", \"message\": \" Request must be object.\"}, \"data\": null}";
    return;
   };
}

////////////////////////////////////////////////////////////////////////////////
/// \brief respond to 'set_ports_setting' command
/// \return answer in string representation

std::string do_set_ports_setting(const JSON_Node *, const JSON_Node * params)
{
 std::string retval = u8"{\n \"status\": { \"code\":";

 const JSON_Node * json_sensors = nullptr;

 if(params)
   {
    if(params->value_type == JSON_ARRAY)
      json_sensors = params;
    else if(params->value_type == JSON_OBJECT)
      json_sensors = params->by_name("addrs");
    else
      {
       retval += "\"clientError\", \"message\":\"Parameters have invalid format.\"}\n}";
       return retval;
      };
   };

 if(!json_sensors)
   {
    retval += "\"serverError\", \"message\":\"Sensors not found.\"}\n}";
    return retval;
   }
 else if(json_sensors->value_type != JSON_ARRAY)
   {
    retval += "\"clientError\", \"message\":\"Sensors must be array.\"}\n}";
    return retval;
   };

 retval += "\"success\", \"message\":\"OK\"}\n}";

 sensor_init();

 std::string empty;
 std::string name;
 std::string addr;
 std::string filter;
 double latency;

 const JSON_Node *part;

 for(auto &el : json_sensors->child) // for each element
   if(el.is_object())        // if type is object
     {
      addr    = ((part = el.by_name("addr"))    && !part->is_compound()) ? part->value : empty;
      filter  = ((part = el.by_name("processingMethod"))  && !part->is_compound()) ? part->value : empty;
      try {
        latency = ((part = el.by_name("latency")) &&  part->is_numeric())  ? std::stod(part->value) : 0.0;
      } catch (...) {latency = 0.0;}

      if(!addr.size()) // mean invalid data
        continue;

      if(!name.size())
        name = addr;

//      sensor_create(name, addr, filter, unit, formula, latency, false);
      sensor_create(name, addr, filter, empty, empty, latency, false);
     };

 // save sensors
 config_save();

 return retval;
}

////////////////////////////////////////////////////////////////////////////////
/// \brief respond to 'start' command
/// \return answer in string representation

std::string do_start(const JSON_Node *, const JSON_Node * params)
{
 std::string retval = u8"{\n \"status\": { \"code\":";
 std::string err_msg;
 bool success = false;

 if(!params)
   {
    retval += "\"clientError\", \"message\":\"Parameters not found.\"}\n}";
    return retval;
   }
 else if(params->value_type != JSON_OBJECT)
   {
    retval += "\"clientError\", \"message\":\"Parameters must be JSON object.\"}\n}";
    return retval;
   };

 // clear existing session if needed
 if(sessions.find(0) != end(sessions))
   sessions.erase(0);

 std::vector<SensorID> sens_id;
 std::vector<std::string> sens_addr;
 int count = -1;     // default value
 double delay = 1.0; // default value

 while(true) {

 const JSON_Node * sens_node = params->by_name("addrs");

 // prepare sensor list
 if(sens_node && (sens_node->value_type == JSON_ARRAY))
   {
    if(sens_node->size())
      {
       Sensor * p_sens;

       for(auto & sens : sens_node->child)
         if((p_sens = sensor_by_addr(sens.value)))
           {
            sens_id.push_back(p_sens->id);
            sens_addr.push_back(sens.value);
           }
         else
           err_msg += "Sensor '" + sens.value + "' not found. ";

       if(!sens_addr.size())
         err_msg += "Parsed sensor list is empty. ";
      }
    else
     err_msg += "Sensor list can't be empty. ";
   }
 else
   err_msg += "Sensor list must be an array. ";

 const JSON_Node * _count = params->by_name("count");
 const JSON_Node * _delay = params->by_name("delay");

 if(_count)
   {
    if(_count->value_type == JSON_NUMERIC)
      {
       try
         {
          count = int(std::stod(_count->value));
          if(count < 0)
            err_msg += "Measure count must be positive. ";
         }
       catch(...)
         {count = -1; err_msg += "Can't parse 'count'. ";};
      }
    else if(_count->value_type == JSON_NULL) // mean default value
      count = 0;
    else
      err_msg += "Measure count have invalid format. ";
   };

 if(_delay)
   {
    if(_delay->value_type == JSON_NUMERIC)
      {
       try
         {
          delay = std::stod(_delay->value);

          if((delay < 0.0) || ((delay == 0.0) && (count != 1)))
            err_msg += "Measure delay have invalid value. ";
         }
       catch(...)
         {delay = -1; err_msg += "Can't parse 'delay'. ";};
      }
    else if(_delay->value_type == JSON_NULL) // mean default value
      delay = 1.0;
    else
      err_msg += "Measure delay have invalid format. ";
   };

  success = (delay > 0.0) && (count > 0) && sens_addr.size(); // && !err_msg.empty();
  break;
 };

 retval += (success)
   ? "\"success\", \"message\":\"OK\"}\n}"
   : "\"clientError\", \"message\":\"" + err_msg +"\"}\n}";

 if(success)
   {
    MeasureSession &sess = sessions[0];

    sess.count = (count) ? count : -1; // -1 mean continous measure
    sess.id = 0;
    sess.interval = to_timeval(delay);
    sess.start    = tv_current;
    swap(sess.sensors_addr, sens_addr);
    swap(sess.sensors_id, sens_id);

    measures_hook_schedule(tv_current, sess.id, 0);

    // TODO: save config here
    // save_config();
   };

 return retval;
}

////////////////////////////////////////////////////////////////////////////////
/// \brief respond to 'stop' command
/// \return answer in string representation

std::string do_stop(const JSON_Node *, const JSON_Node * params)
{
 std::string retval = u8"{\n \"status\": { \"code\":";

 int sess_id = 0;

 // try to extract session ID
 if(params && (params->value_type == JSON_OBJECT))
   {
    const JSON_Node *tmp = params->by_name("session-id");

    if(tmp && (tmp->value_type == JSON_NUMERIC))
      try {sess_id = std::stod(tmp->value);}
      catch(...) {sess_id = 0;};
   };

 auto it_sess = sessions.find(sess_id);

 if(it_sess == end(sessions))
   {
    retval += "\"serverError\", \"message\":\"No measures found.\"}\n}";
    return retval;
   }
  else
   {
    it_sess->second.count = 0;
    retval += "\"success\", \"message\":\"OK\"}\n}";
   };

 return retval;
}

////////////////////////////////////////////////////////////////////////////////
/// \brief respond to 'get_values' command
/// \return answer in string representation

std::string do_get_values(const JSON_Node *, const JSON_Node * params)
{
 std::string retval = u8"{\n \"status\": { \"code\":";

 const JSON_Node *json_sensors = nullptr;
 int sess_id = 0;
 int i = 0;

 if(params) // can be optional
   {
    if(params->value_type == JSON_OBJECT)
      {
       const JSON_Node *tmp;

       // try to extract session ID
       tmp = params->by_name("session-id");

       if(tmp && (tmp->value_type == JSON_NUMERIC))
         try {sess_id = std::stod(tmp->value);}
         catch(...) {sess_id = 0;};

       // try to extract sensors list
       tmp = params->by_name("addrs");

       if(tmp && (tmp->value_type == JSON_ARRAY))
         json_sensors = tmp;
      }
    else if(params->value_type == JSON_ARRAY)
      json_sensors = params;  // mean parameters is sensors list
    else
      {
       retval += "\"clientError\", \"message\":\"Can't parse parameters.\"}\n}";
       return retval;
      }
   };

 auto it_sess = sessions.find(sess_id);

 if(it_sess == end(sessions))
   {
    retval += "\"serverError\", \"message\":\"No measures found.\"}\n}";
    return retval;
   };

 std::vector<std::string> sens_list;
 MeasureSession &sess = it_sess->second;

 // extract sensor list
 if(json_sensors)
   {
    sens_list.clear();
    sens_list.resize(sess.sensors_addr.size());

    std::vector<std::string>::iterator it_msens;
    std::vector<std::string>::iterator it_msens_end = end(sess.sensors_addr);

    for(auto & sens_id : sens_list) // mark id's as unused
      sens_id = "";

    // for each requested addr
    for(auto & sens : json_sensors->child)
      {
       it_msens = begin(sess.sensors_addr); i = 0;

       // looking for sessions sensors
       while(it_msens != it_msens_end)
         {
          if(*it_msens == sens.value)
            sens_list[i] = sens.value;

          ++it_msens; ++i;
         }; // iterate session sensors
      }; // iterate requested sensors
   }; // fill sensor list

 // if requested list not builded
 if(!sens_list.size())
   sens_list = sess.sensors_addr; // use session sensors by default

 // make responce

 retval += "\"success\", \"message\":\"OK\"},\n \"data\":\t{\"addrs\": [";

 // form sensor list
 for(auto & addr : sens_list)
   if(addr.size())
     retval += '\"' + addr + "\",";

 if(retval.back() == ',')
   retval.resize(retval.size()-1); // trim last char

 // form result rows

 retval += "],\n\t \"values\": [";

 while(sess.results.size()) // for each result row
   {
    retval += "\n\t\t  [";

    ResultRow &row = sess.results.front();

    i = 0;

    for(auto & result : row)
      if(sens_list[i].size())
        {
         retval += ' ' + result + ',';
         ++i;
        };

    if(retval.back() == ',')
//      retval.erase(retval.size()-1); // trim last char
      retval.resize(retval.size()-1);

    retval += "],";
    sess.results.pop_front();
   };

  if(retval.back() == ',')
//    retval.erase(retval.size()-1); // trim last char
    retval.resize(retval.size()-1);

 retval += "\n\t\t]\n\t}\n}";

 return retval;
}

////////////////////////////////////////////////////////////////////////////////
/// \brief respond to 'update' command
/// \return answer in string representation

std::string do_update(const JSON_Node *, const JSON_Node * params)
{
 std::string retval = u8"{\n \"status\": { \"code\":";
 const JSON_Node * tmp = nullptr;

 std::string name;
 std::string target_dir;
 std::string data;


 if(params && (params->value_type == JSON_OBJECT))
   {
    if((tmp = params->by_name("name")) && (tmp->value_type == JSON_STRING))
      name = tmp->value;
    if((tmp = params->by_name("data")) && (tmp->value_type == JSON_STRING))
      data = tmp->value;

    if(name.empty() || data.empty())
      retval += "\"clientError\", \"message\":\"incomplete command.\"}\n}";
    else
      {
       size_t src_cnt = data.size();
       size_t dst_cnt = src_cnt*3/4;
       size_t decoded;
       std::vector<uint8_t> buff;

       buff.reserve(dst_cnt);

       decoded = base64_decode(data.c_str(), (char *) buff.data(), src_cnt);

       if(decoded > (dst_cnt - 3))
         {
          std::ofstream file;

          target_dir =  (name == "interfaces") ? "/etc/network/" : "/var/tmp/";

          file.open(target_dir + name, std::ofstream::binary | std::ofstream::trunc);

          if(file.is_open())
             file.write((char*) &buff[0], decoded);

          if(file.good())
            {
             if(!name.compare(0, 6, "update"))
               retval += "\"success\", \"message\":\"OK\"}\n}";
             else if(!selfupgrade(target_dir + name))
               retval += "\"success\", \"message\":\"Upgrade suceessfully finished.\"}\n}";
             else
               {
                std::string err(strerror(errno));
                std::replace_if(begin(err), end(err), [](std::string::value_type c){return c == '"';}, '\'');
                retval += "\"serverError\", \"message\":\"Upgrade failed: " + err + "\"}\n}";
               };
            }
          else
            {
             retval += "\"serverError\", \"message\":\"";
             std::string err(strerror(errno));
             std::replace_if(begin(err), end(err), [](std::string::value_type c){return c == '"';}, '\'');
             retval += err + "\"}\n}";
            };

          unlink((target_dir + name).c_str());
          file.close();
         }
       else
         retval += "\"serverError\", \"message\":\"can't decode data.\"}\n}";
      };
   }
 else
   retval += "\"clientError\", \"message\":\"'params' must be object.\"}\n}";

 return retval;
}

////////////////////////////////////////////////////////////////////////////////
/// \brief respond to 'restore' command
/// \return answer in string representation

std::string do_restore(const JSON_Node *, const JSON_Node *)
{
 std::string retval = u8"{\n \"status\": { \"code\":\"success\", \"message\":\"OK\"}\n}";

 config_restore();

 return retval;
}

////////////////////////////////////////////////////////////////////////////////
/// \brief respond to 'get_info' command
/// \return answer in string representation

std::string do_get_info(const JSON_Node *, const JSON_Node *)
{
 std::string retval = u8"{\n \"status\":\t{ \"code\":\"success\", \"message\": \"OK\"},\n";

 retval += " \"data\":\t{\"version\": \"";
 retval += VERSION_STRING; // defined in constants.hpp
 retval += "\", \"verification\": \"";

 retval += (is_valid) ? "done" : "fail"; // verification status

 retval += "\"}\n}";

 return retval;
}
////////////////////////////////////////////////////////////////////////////////
/// \brief respond to 'get_status' command
/// \return answer in string representation

std::string do_get_status(const JSON_Node *, const JSON_Node *)
{
 std::string retval = u8"{\n \"status\":\t{ \"code\":\"success\", \"message\": \"OK\"},\n";

 retval += " \"data\":\t{\"verification\": \"";

 retval += (is_valid) ? "done" : "fail"; // verification status

 retval += "\"}\n}";

 return retval;
}
