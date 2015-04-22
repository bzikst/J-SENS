# J-SENS
Open protocol for receiving measured sensors data.

### Introduction


J-SENS — open application layer communication protocol, using [HTTP](https://en.wikipedia.org/wiki/Hypertext_Transfer_Protocol) for data transfer. All data is in UTF-8 encoding, structured in [JSON](https://en.wikipedia.org/wiki/JSON) format. This protocol has a client-server architecture, commonly with one master device (acting as a client) sending commands to slave devices (servers), collecting measured sensors data. But there are no any restrictions on how many devices are involved into interaction. Data transfer is based on transactions, consisting of the request and response. Master device initiates a transaction by passing commands as requests, and the slave responds by telling status of the response and returning result of the command.

To identify the device in particular case of using protocol within one broadcast domain broadcast [UDP](https://en.wikipedia.org/wiki/User_Datagram_Protocol)-Packages are used. These packets are sent via port number initially known by all interacting devices. Thus, master devices can recognize ids of slave devices in active mode in the same network without presetting.

J-SENSE was originally developed using common protocols such as TCP, HTTP and JSON unified data format. This simplifies development tools selection procedure and, on the other hand, takes into account all best practices implemented in widely used protocols such as [MODBUS](https://en.wikipedia.org/wiki/Modbus), [PROFINET](https://en.wikipedia.org/wiki/PROFINET), [CANopen](https://es.wikipedia.org/wiki/CANopen), etc.

### Terms and definitions

##### Terms


Device — a controller with sensors, acts as server in a client-server architecture. This protocol does not specify sensor and controller interaction, and treats sensor as a device which transfer measurements in form, suitable to interpretation by a controller.

Client — master device, which requests data from slave devices, acts as client in a client-server architecture. 

##### Definitions


[<a>] — an array of elements of single type, can be empty

{} — a set of named comma-separated elements

![Network scheme](https://github.com/bzikst/J-SENS/blob/master/network_scheme.png)

### Description


Device application layer is implemented as web-server, accepting HTTP requests from clients. The device stores sensors metadata (obligatory information is sensor physical address and port) and contains at least one virtual counter sensor. Upon activating, the device broadcasts UDP packet with header in following format: `{CODENAME}_v{VERSION}_p{PORT}`, thus confirms being online.

##### Common device request format
```
{
	cmd: <command: string>,
	params: <parameters>
}
```

##### Common device response format

```
{
	status: {code: <response code (success or fail): строка>, message: <message: string>},
	<data>: <arbitrary data>	
}
```

### Requests and responses

Device does support following requests:
- `get-status` — get device status, `params = {}`.
- `get-info` — get device info, `params = {}`.
- `update` — update device firmware, `params = {name, data}`, `data` — base64 encoded data.
- `start` — measurement preparation, `params = {count, delay, sensors: [addr1, addr2, …]}`, where `count` — sample count, `delay` — delay between samples in seconds, `addrN` — sensor address.
- `get-values` — get data from sensors, `params = {addrs: [addr1, addr2]}`, где `addrN` — sensor address.
- `set-ports-setting` — send port information, `params = [{addr: addr1, proccessingMethod: method1}, {addr: addr2, proccessingMethod: method2}, …]`

Device responses have following format:
```
get-status:
{
	status,
	data: {verification}
}

get-info:
{
	status,
	data: {verification, version, protocol}
}
```

`set-ports-setting` и `start` — возвращают только статус:
```
{status: …}
```

```
get-values: 
{
	status: {code: "success", message: "OK"},
	data: {sensors: [addr1, addr2, …], values: [row1, row2, row3 …]}
}
```

where `addrN` — sensor address (assuming the data was requested from `k` sensors), 
`rowN = [v1, v2, …, vk]` — data array (table row) with `k` elements. Element `vN` corresponds to data, taken from sensor with address `addrN`.

### Work scheme 


1. Device is switched on.
2. Device is sending broadcast UDP-packet saying `{CODENAME}_v{VERSION}_p{PORT}` (with some time intervals).
3. Master device receiving packet.
4. In case of unknown device, master is sending `get-info` request.
5. In case of known device, master is sending `get-status` command.
6. Master device is updating slave devices information limited to once in 5 seconds.
8. Device information is removed If slave device is not responding to `get-info` request.
9. User wants to get N measurements with M seconds delay.
10. Particular slave device gets `start` command.
11. If `start` command is accepted, master device is starting to send `get-values` request in M seconds each till it gets N responses or error occurs.

All HTTP responses are required to be sent as fast as possible, not depending on possible measurement delays. Such empty responses are correct:
```
{
	status: {code: "success", message: "OK"},
	data : {sensors: [addr1, addr2], values: [[]]}
},
```


so are responses with data gathered earlier but not sended to master device:

```
{
	status: {code: "success", message: "OK"},
	data : {sensors: [addr1, addr2], values: [[1,61],[80,3]]}
}
```


Requests and responses strictly follow JSON specification. Thus, payload should be like: `{“cmd”: “get-sensors”}`. All primitive values, including numbers in `get-values` response, should be sent as strings and be quoted.

### Acknowledgements

Developers of J-SENS protocol appreciate [Фонд содействия МП НТС](http://www.fasie.ru/) for its support .

### References

1. Modbus Organization. April 26, 2012. MODBUS APPLICATION PROTOCOL SPECIFICATION V1.1b3. Retrieved from: http://www.modbus.org/docs/Modbus_Application_Protocol_V1_1b3.pdf

2. R. Fielding, UC Irvine, J. Gettys et al. June 1999. Hypertext Transfer Protocol -- HTTP/1.1. Retrieved from: https://tools.ietf.org/html/rfc2616

3. T. Bray, Ed. Google, Inc. March 2014. The JavaScript Object Notation (JSON) Data Interchange Format. Retrieved from: https://tools.ietf.org/html/rfc7159

4. PI Organization. Specifications & Standards. Retrieved from: http://www.profibus.com/download/specifications-standards/

5.  CAN in Automation (CiA). CANopen protocols. Retrieved from: http://www.can-cia.org/index.php?id=systemdesign-canopen-protocol

6. Telecommunications Industry Association (TIA). 12/07/12. TIA-485-A ELECTRICAL CHARACTERISTICS OF GENERATORS AND RECEIVERS FOR USE IN BALANCED DIGITAL MULTIPOINT SYSTEMS. Retrieved from: https://global.ihs.com/search_res.cfm?input_doc_number=TIA-485-A&input_doc_title=&rid=TIA

