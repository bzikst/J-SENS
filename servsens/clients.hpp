////////////////////////////////////////////
// Clients example module for J-SENS protocol
// Originally written by Alexander Gakhov
// Contributors: Alexey Mikhaylishin, Konstantin Moskalenko
// See https://github.com/bzikst/J-SENS for details

#ifndef _CLIENTS_HPP_
#define _CLIENTS_HPP_

// some internal dependencies was here

/// store client data
struct Client
{
 /// construct client data
 Client(int _socket = 0 /**< client socket */)
    : input(), output(), request(), respond(), sock(_socket), buff_length(0)
    {input.reserve(BUFF_IN_SIZE); output.reserve(BUFF_OUT_SIZE);};

 /// do client data processing
 void process();
 bool parse_request(void) {return parse_http_request(request, (char *)buff, &buff_length);}
 void make_response(int code = 200) {make_http_response(output, respond, code);}


 std::string input;  ///< input buffer
 std::string output; ///< output buffer

 HttpInfo request;   ///< hold request data
 HttpInfo respond;   ///< used to build responce

 SocketHolder sock;  ///< client socket

 uint8_t buff[4096];  ///< buffer to read from socket
 size_t  buff_length; ///< unparsed data in buffer
};

typedef std::map<int, Client> ClientPool; ///< maps socket to client data

extern ClientPool Clients; ///< hold all client's data

#endif
