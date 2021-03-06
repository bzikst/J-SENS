# J-SENS
Открытый протокол получения данных измерений с датчиков. Версия этого файла на английском [здесь](https://github.com/bzikst/J-SENS/blob/master/README.rus.md).

### Введение 

J-SENS — открытый коммуникационный протокол прикладного уровня, использующий в качестве инструмента передачи данных [HTTP](https://ru.wikipedia.org/wiki/HTTP). Все данные передаются в формате [JSON](http://ru.wikipedia.org/wiki/JSON), кодировке UTF-8. Протокол имеет клиент-серверную архитектуру, чаще всего с одним клиентом (ведущим устройством, собирающим данные измерений), управляющим остальными (ведомыми, отдающими данные измерений) устройствами, однако ограничения на количество устройств каждого типа не вводятся. Взаимодействие основано на транзакциях, состоящих из запроса и ответа. Ведущее устройство инициирует транзакции, передавая запросы с командами, а ведомое отвечает, сообщая статус ответа и возвращая результат выполнения команды.

Для идентификации устройства в частном случае применения протокола в пределах одного широковещательного домена используются broadcast [UDP](https://ru.wikipedia.org/wiki/UDP)-пакеты, отправляемые на порт, заранее известный всем участвующим в обмене устройствам. Таким образом, ведущие устройства могут узнавать идентификаторы ведомых устройств, присутствующих в данной сети в активном режиме, без предварительной настройки.

J-SENS изначально разрабатывался с использованием широко распространенных протоколов TCP, HTTP и унифицированным форматом передачи данных JSON. Это упрощает поиск средств для реализации обмена и позволяет абстрагироваться от знаний технологических тонкостей работы датчиков, с одной стороны, а, с другой стороны, позволяет учитывать лучшие практики реализованные в протоколах и получивших широкое распространение в индустрии, такие как [MODBUS](https://ru.wikipedia.org/wiki/Modbus), [PROFINET](https://ru.wikipedia.org/wiki/PROFINET) или [CANopen](https://ru.wikipedia.org/wiki/CANopen) и др.

### Используемые термины и обозначения

##### Термины
Устройство — cовокупность контроллера с датчиками, является ведомым устройством и выступает в роли сервера в клиент-серверной архитектуре. Данный протокол не рассматривает взаимодействие контроллера с физическим сенсором и рассматривает датчик как совокупность устройства измерений и средства преобразования полученной величины в интерпретируемое контроллером значение.

Клиент — ведущее устройство, запрашивающий данные с ведомых устройств, выполняет роль клиента в клиент-серверной архитектуре.

##### Обозначения
[<a>] — массив однотипных значений <a>, может быть пустым.

{} — содержит множество именованных значений, разделенных запятой.

![Network scheme](https://github.com/bzikst/J-SENS/blob/master/network_scheme_rus.png)

### Общее описание

Устройство на программном уровне реализует веб-сервер, принимающий HTTP-запросы от клиентов. Устройство хранит в себе информацию о датчиках (необходимой информацией является физический адрес/порт датчика) и содержит в себе, по крайней мере один виртуальный датчик — датчик времени. При старте устройство посылает в сеть широковещательный UDP пакет c кодовым словом формата `{CODENAME}_v{VERSION}_p{PORT}`, сообщая что устройство в сети. 

##### Общий формат команд для устройства
```
{
	cmd: <команда: строка>,
	params: <параметры>
}
```

##### Общий формат ответа от устройства

```
{
	status: {code: <код ответа (success или fail): строка>, message: <сообщение: строка>},
	<data>: <некоторые данные>	
}
```

### Запросы к устройству и его ответы

Устройство поддерживает команды:
- `get-status` — получить статус устройства, `params = {}`.
- `get-info` — получить информацию об устройстве, `params = {}`.
- `update` — отправить обновления на устройство, `params = {name, data}`, `data` — закодировано base64.
- `start` — подготовка к измерениям, `params = {count, delay, sensors: [addr1, addr2, …]}`, где `count` — количество измерений, delay — ожидаемое время между измерениями, секунды, `addrN` — адрес датчика.
- `get-values` — получить значения с датчиков, `params = {addrs: [addr1, addr2]}`, где `addrN` — адрес датчика.
- `set-ports-setting` — отправить информацию о портах, `params = [{addr: addr1, proccessingMethod: method1}, {addr: addr2, proccessingMethod: method2}, …]`

Устройства отвечает на команды:

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

где `addrN` — адрес датчика (пусть запрошены измерения с k датчиков), 
`rowN = [v1, v2, …, vk]` — массив с данными(строка таблицы), длиной равной k. Каждое число vN соответствует значению снятому с датчика `addrN`.

### Схема работы

1. Включается устройство.
2. Устройство посылает широковещательный UDP пакет с фразой `{CODENAME}_v{VERSION}_p{PORT}` (с определённой частотой).
3. Клиент получает пакет.
4. Если устройство новое, то клиент отправляет на устройство запрос `get-info`.
5. Если устройство уже добавлено, то клиент посылает команду `get-status`.
6. Клиент обновляет у себя информацию об устройствах, не чаще чем каждые 5 секунд.
8. Если устройство недоступно (не отвечает на команду `get-info`), то устройство удаляется.
9. Пользователь запрашивает N измерений с интервалом M секунда.
10. На устройство приходит команда `start`, с соответствующими параметрами.
11. Если ответ положительный, клиент начинает опрашивать (`get-values`) устройство с интервалом M секунд, пока не получит N измерений или пока не произойдет ошибка соединения.

Требования к HTTP ответам от устройства — максимально быстрый отклик, то есть время отклика не должно определяться временем измерения с датчика. Таким образом возможны пустые ответы: 

```
{
	status: {code: "success", message: "OK"},
	data : {sensors: [addr1, addr2], values: [[]]}
},
```

а также ответы со значениями полученными раннее, но не отправленными серверу:

```
{
	status: {code: "success", message: "OK"},
	data : {sensors: [addr1, addr2], values: [[1,61],[80,3]]}
}
```

Запросы и ответы строго используют спецификацию JSON. То есть должно быть: `{"cmd": "get-sensors"}`. Все элементарные значения, в том числе числа в ответе на запрос `get-values` — передаются как строковый тип и заключаются в кавычки.

### Благодарности

Разработчики протокола J-SENS благодарят за поддержку [Фонд содействия МП НТС](http://www.fasie.ru/).

### Источники

1. Modbus Organization. MODBUS APPLICATION PROTOCOL SPECIFICATION V1.1b3 [Электронный ресурс]:  April 26, 2012. Режим доступа: http://www.modbus.org/docs/Modbus_Application_Protocol_V1_1b3.pdf

2. R. Fielding, UC Irvine, J. Gettys etc. Hypertext Transfer Protocol --HTTP/1.1 [Электронный ресурс]: June 1999. Режим доступа: https://tools.ietf.org/html/rfc2616

3. T. Bray, Ed. Google, Inc. The JavaScript Object Notation (JSON) Data Interchange Format [Электронный ресурс]: March 2014. Режим доступа: https://tools.ietf.org/html/rfc7159

4. Specifications & Standards: [Электронный ресурс] // PI Organization. Режим доступа: http://www.profibus.com/download/specifications-standards/

5. CANopen protocols: [Электронный ресурс] // CAN in Automation (CiA) Режим доступа: http://www.can-cia.org/index.php?id=systemdesign-canopen-protocol

6. TIA-485-A ELECTRICAL CHARACTERISTICS OF GENERATORS AND RECEIVERS FOR USE IN BALANCED DIGITAL MULTIPOINT SYSTEMS: [Электронный ресурс] // Telecommunications Industry Association (TIA). 12/07/12. Режим доступа: https://global.ihs.com/search_res.cfm?input_doc_number=TIA-485-A&input_doc_title=&rid=TIA
