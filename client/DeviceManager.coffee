# Device manager example module for J-SENS protocol
# Originally written by Denis Shirokov
# Contributors: Ivan Orlov, Alexey Mikhaylishin, Konstantin Moskalenko
# See https://github.com/bzikst/J-SENS for details
#

require 'coffee-script'

# Внешние модули
#
dgram       =   require 'dgram'
http        =   require 'http'
querystring =   require 'querystring'
crypto      =   require 'crypto'
fs          =   require 'fs'
path        =   require 'path'
# Ошибки устройств
#

class DeviceError extends Error
  constructor: (code, error)->
    @code = code
    @error = error


# Отправить комманду на устройство
#
sndCmd = (host, port, params, timeout, cb)->
  sendData = JSON.stringify params
  options =
    method: 'POST', host: host, port: port,
    headers:
      'Content-Type': 'application/json'
      'Content-Length': Buffer.byteLength(sendData)

  Logger.debug """
                  На адрес #{host}:#{port} отправленны данные
                  #{sendData}
               """
  # установить обработчик полученных данных
  req = http.request options, (res)->
    data = ''
    res.on 'data', (chunk)-> data += chunk
    res.on 'end', ()->
      Logger.debug "Данные с контроллера #{data}"

      try
        jsonData = JSON.parse data

        cb.done? jsonData
      catch error
        Logger.debug('Ошибка parse error', error)
        Logger.debug('Parse data', data)
        cb.fail? DeviceError 'parseerror', error

  # определить максимальное время запроса
  req.setTimeout timeout, ()->
    cb.fail? DeviceError 'timeout'
    req.abort()

  # обработать ошибку
  req.on 'error', (error)->
    Logger.debug('Ошибка request error', error)
    cb.fail? DeviceError 'noresponse', error

  # сделать запрос
  req.write sendData
  req.end()


# Логгер
#
debug = global.debug;
Logger =
  debug: ->
    if debug
      console.log('Logger debug >>>')
      console.log.apply(console, arguments)
      console.log('Logger ---\n')
  info: ->
    console.log('Logger info >>>')
    console.log.apply(console, arguments)
    console.log('Logger ---\n')

CONFIG =
# файл с обновлением
  UPDATE_FILE: './update.data'
# файл с описанием обновления
  UPDATE_INFO: './update.json'

# Утсройство
#
class Device
  constructor: (host, port, uid)->
    @verification = null
    @version = null
    @protocol = null
    @host = host
    @port = port
    @uid = crypto
    .createHash('md5')
    .update(uid)
    .digest('hex')
    @haveupdate = no
    @lastUpdate = Date.now() # время последнего обновления
    @id = crypto
    .createHash('md5')
    .update(host + ':' + port)
    .digest('hex')

  toString: ->
    """
      Устройство #{@uid}
      id: #{@id}
      хост: #{@host}:#{@port}
      требует обновления: #{@haveupdate}
      подлинность: #{@verification}
    """

  toJSON: ->
    {
    id: @id
    uid: @uid
    verification: @verification
    haveupdate: @haveupdate
    protocol: @protocol
    version: @version
    }

  # получить статус устройства
  #
  getStatus: (deviceManager)->
    sndCmd @host, @port, {cmd: 'get-status'}, DeviceManager._DEV_TIMEOUT,
      done: (res) =>
        # если ответ положительный, статус изменени, то оповестить клиенты
        if res.status? and DeviceManager.RES_SUCCESS is res.status.code
          if res.data?.verification isnt @verification
            @verification = res.data.verification
            deviceManager.change(@id, 'status')
            Logger.debug('Получен ответ об на get-status, статус изменился')
          else
            Logger.debug('Получен ответ об на get-status, статус остался прежнем')
        else
          Logger.info('Неверный ответ на get-status от устройства:\n', @toString(), 'ответ:', res)

      fail: (err) =>
        Logger.info('Не получен ответ на get-status, устройство', @toString(), ' будет удалено')
        deviceManager.remove(@id, 'noresponse')

  # получить информацию об устройстве
  #
  getInfo: (deviceManager)->
    Logger.debug('getInfo', @)
    sndCmd @host, @port, {cmd: 'get-info'}, DeviceManager._DEV_TIMEOUT,
      done: (res) =>
        if res.status? and DeviceManager.RES_SUCCESS is res.status.code
          @verification = res.data?.verification
          @version = res.data?.version
          @protocol = res.data?.protocol

          # проверить обновление
          if @checkUpdate(deviceManager.updateInfo) is 'critical'
            @haveupdate = yes
            @sendUpdate deviceManager,
              done: =>
                deviceManager.remove(@id, 'updating')
              fail: (err)=>
                Logger.debug('При отправки update на ', @toString(), 'произошла ошибка', err)
          else if @checkUpdate(deviceManager.updateInfo) is 'normal'
            @haveupdate = yes
            deviceManager.add(@id, 'new')
          else
            deviceManager.add(@id, 'new')
        else
          Logger.info('Неверный ответ на get-info от устройства:', @toString(), 'ответ:', res)
      fail: (err) =>
        Logger.info('Не получен ответ на get-info, устройство', @toString(), ' будет удалено')
        deviceManager.remove(@id, 'noresponse')

  # проверить, требуется ли обновление
  #
  checkUpdate: (updateInfo)->
    unless updateInfo? then return 'noupdate'
    min = Number(updateInfo.version.min)
    max = Number(updateInfo.version.max)
    cv = Number(@version)
    console.log(min, cv, max)
    # проверить версию
    if min <= cv < max
      if 'critical' is updateInfo.priority
        return 'critical'
      else
        return 'normal'
    else
      return 'noupdate'

  # отправить обновления на устройство
  #
  sendUpdate: (deviceManager, cb)->
    fs.readFile CONFIG.UPDATE_FILE, (err, data)=>
      unless err?
        sndCmd @host, @port, {cmd: 'update', params: {name: deviceManager.updateInfo.name, data: data.toString('base64')}}, DeviceManager._DEV_TIMEOUT,
          done: (res) =>
            if res.status? and DeviceManager.RES_SUCCESS is res.status.code
              Logger.debug('Получен ответ на update, устройство', @toString(),'будет обновленно')
              deviceManager.remove(@id, 'updating')
              cb.done?(res)
            else
              Logger.info('Неверный ответ на update от устройства:', @toString(), 'ответ:', res)
              cb.fail?(err)
          fail: (err) =>
            Logger.info('Не получен ответ на update, устройство', @toString(), ' будет удалено')
            deviceManager.remove(@id, 'noresponse')
            cb.fail?(err)
      else
        cb.fail?(Error())

  # пробросить комманду
  #
  proxyCommand: (deviceManager, params, cb)->
    # перехватить команду на обновление
    if 'update' is params.cmd
      if @checkUpdate(deviceManager.updateInfo) in ['critical', 'normal']
        @sendUpdate deviceManager,
          done: (res)=>
            cb.done?(res)
          fail: (err)=>
            cb.fail?(err)
      else
        Logger.info('Получен запрос на обновления, но обновлений нет, для:', @toString())
        cb.fail?(Error())
    else
      sndCmd @host, @port, params, DeviceManager._DEV_TIMEOUT, cb


# Менеджер устройств
#
# Сообщения клиенту
#   update [devices] - отправить подключенному клиенту массив устройств
#   change device - отправить клиенту обновленное утсройство
#   remove id msg - отправить клиенту сообщение об удалении устройства id и поясняющее сообщение msg
#
_instance = null
class DeviceManager
  @_HELO_MSG: /[a-z0-9_-]+_v[a-z0-9.-]_p[0-9]+]/
  @_DEV_HTTP_PORT : 8080
  @_DEV_UDP_PORT  : 3000  # udp порт
  @_DEV_UPD_TIME  : 1000  # ms таймоут после которого мы просим обновить устройство
  @_DEV_REF_TIME  : 10000 # ms таймоут после которого мы принудительно обновляем устройство, и если оно не подтверждено удаляем его
  @_DEV_TIMEOUT   : 5000  # ms таймоут после которого считается что устройство не доступно
  udpSct          : null
  sockets         : null  # client socket connection
  devices         : null  # devices hash table
  hTimer          : null
  updateInfo      : null
  @RES_SUCCESS    : 'success'

  @Instance: ()->
    unless _instance?
      _instance = new DeviceManager
    return _instance

  constructor: ()->
    @sockets = []
    @devices = {}
    @readUpdateInfo()
    @start()

  # прочитать файл обновлений
  #
  readUpdateInfo: ->
    fs.readFile CONFIG.UPDATE_INFO, {flag: 'r'}, (err, data)=>
      unless err?
        try
          updateInfo = JSON.parse(data.toString())
          if updateInfo.version?.min? and updateInfo.version?.max?
            @updateInfo = updateInfo
            Logger.debug('Файл с обновлениями прочитан')
          else
            Logger.info('Неверный формат файла с обновлениями:', data.toString(), updateInfo)
        catch err
          Logger.info('Неверный формат файла с обновлениями(json parse error):', data.toString(), err)
      else
        Logger.info('Ошибка чтения файла с обновлениями:', CONFIG.UPDATE_INFO)
        Logger.debug(err)

  # старт менеджера устройств
  #
  start: =>
    @udpSct = dgram.createSocket 'udp4'
    @udpSct.on 'listening', @udpOnListening
    @udpSct.on 'message', @udpOnMessage
    @udpSct.bind DeviceManager._DEV_UDP_PORT
    @hTimer = setInterval @forceUpdate, DeviceManager._DEV_REF_TIME

  # стоп менеджера устройств
  #
  stop: () ->
    @udpSct.close()
    @devices = null
    @sockets.length = 0
    clearInterval @hTimer

  # добавить подключенный клиент
  #
  connect: (socket)->
    @sockets.push socket
    # отдать клиенту информацию об устройствах
    socket.emit 'update', @toJSON()
    socket.emit 'disconnect', ()=>
      @disconnect socket

  # удалить отключенный клиент
  #
  disconnect: (socket)->
    index = @sockets.indexOf socket
    @sockets.splice index, 1

  # обработать сообщение
  #
  udpOnMessage: (buff, rinfo)=>
    msg = buff.toString()
    Logger.debug "server got #{msg} from #{rinfo.address}:#{rinfo.port}"
    # нужна проверка
    if DeviceManager._HELO_MSG.test msg
      # новое подключенное устройство
      host = rinfo.address
      port = DeviceManager._DEV_HTTP_PORT
      @tryUpdate host, port, msg

  # обрботать событие началот прослушивания порта udp
  #
  udpOnListening: ()=>
    addr = @udpSct.address()
    Logger.info "UDP Server listening on #{addr.address}:#{addr.port}"

  # обновить по событию таймера
  #
  forceUpdate: =>
    time = Date.now()
    for id, device of @devices
      timeout = time - device.lastUpdate
      if timeout > DeviceManager._DEV_UPD_TIME
        device.lastUpdate = Date.now()
        device.getStatus(@)

  # обновить по событию от устройства
  #
  tryUpdate: (host, port, uid)->
    id = crypto
    .createHash('md5')
    .update(host + ':' + port)
    .digest('hex')
    time = Date.now()

    device = @devices[id]
    unless device?
      # устройства нет в списке
      @devices[id] = new Device(host, port, uid)
      @devices[id].getInfo(@)
    else
      # устройство есть в списке
      timeout = time - device.lastUpdate
      if timeout > DeviceManager._DEV_UPD_TIME
        device.lastUpdate = Date.now()
        device.getStatus(@)

  # оповестить об изменение информации об устройстве
  #
  change: (id, msg)->
    device = @devices[id]
    if device?
      jsonDevice = device.toJSON()
      @sockets.forEach (socket)=>
      socket.emit 'change', jsonDevice, msg

  # оповестить об удаление устройства
  #
  remove: (id, msg)->
    delete @devices[id]
    @sockets.forEach (socket)=>
      socket.emit 'remove', id, msg

  # оповестить об удаление устройства
  #
  add: (id, msg)->
    device = @devices[id]
    if device?
      jsonDevice = device.toJSON()
      @sockets.forEach (socket)=>
        socket.emit 'add', id, jsonDevice, msg


  toJSON: ->
    data = []
    for id, device of @devices
      item = JSON.parse JSON.stringify device.toJSON()
      data.push item
    return data

  # передать команду на устройство
  #
  proxyCmd: (id, params, cb)->
    device = @devices[id]
    if device?
      device.proxyCommand(@, params, cb)
    else
      @remove(id, 'notfound')
      cb.fail?(Error('not found'))

module.exports = DeviceManager
