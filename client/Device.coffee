# Device example module for J-SENS protocol
# Originally written by Denis Shirokov
# Contributors: Ivan Orlov, Alexey Mikhaylishin, Konstantin Moskalenko
# See https://github.com/bzikst/J-SENS for details
#

send = (id, cmd, params, cb)->
  deffered = $.ajax "someurl_for_device/#{id}",
    {
      method: 'POST',
      contentType : 'application/json; charset=utf-8;',
      data: JSON.stringify({cmd, params}),
      dataType: 'json'
    }
  deffered
  .done (res)->
    if 'success' is res.status.code
      cb.done?(res.status.code, res.data)
    else
      cb.fail?(Error(res.status))
  .fail (err)-> cb.fail?(err)

# Датчики
#
class Model.Sensor extends Model.MongooseModel

  @dataProcessMethod: [
    {title: 'Не обрабатывать', code: 'none'}
  ]
  default:
    uid: ''
    internal: false
    unit: ''
    title: 'undefined'
    proccesingMethod: 'none'
    format: 'f'
    formula: 'x'



SENSORS_TAB = [
  {title: 'Дальномер LV MaxSonar-EZ3', proccesingMethod: 'none', id: 's0', format: 'f3', formula: '(x-0.09)*799+72.7', unit: 'metr', uid: 's0', internal: false, type: 'embeded'}
  {title: 'Датчик освещенности', proccesingMethod: 'none', id: 's1', format: 'f3', formula: 'x*3600', unit: 'luks', uid: 's1', internal: false, type: 'embeded'}
  {title: 'Датчик температуры окружающей среды', proccesingMethod: 'none', id: 's2', format: 'f3', formula: 'x*250', unit: 'cels', uid: 's2', internal: false, type: 'embeded'}
  {title: 'Датчик температуры жидкости', proccesingMethod: 'none', id: 's3', format: 'f3', formula: '(x/(5/3-x)-1)*260', unit: 'cels', uid: 's3', internal: false, type: 'embeded'}
  {title: 'Датчик атмосферного давления', proccesingMethod: 'none', id: 's4', format: 'f3', formula: 'x', unit: 'pas', uid: 'plessure', internal: true, type: 'embeded'}
  {title: 'Время', proccesingMethod: 'none', id: 's5', format: 'f3', formula: 'x', unit: 'pas', uid: 'time', internal: true, type: 'embeded'}
]

class Model.Sensors extends Model.MongooseCollection
  model: Model.Sensor

  @instance: ->
    unless Model.Sensors._instance? then Model.Sensors._instance = new Model.Sensors
    return Model.Sensors._instance

  getByUid: (uid)->
    return @find({uid})

  initCollection: ->
    sensors = SENSORS_TAB
    @reset(sensors)

  restore: ->
    @reset(SENSORS_TAB)



Model.Sensors.instance().initCollection()


class Model.MesurmentFromDevice
  devices: null
  hatch: null
  mesurment: null

  constructor: (mesurment, devices)->
    @mesurment = mesurment

    if devices.devices? and devices.tableMap?
      @devices = JSON.parse JSON.stringify devices.devices
    else
      @devices = {}

    @hatch = {}

  addSource: (uid, addr, colNum)->
    unless @devices[uid]? then @devices[uid] = []
    # список устройств и датчиков
    @devices[uid].push addr


  start: (getDelay, count, updateDelay, cb)->
    sensors = Model.Sensors.instance()
    devices = Model.Devices.instance()

    for id, addrs of @devices
      params = addrs.map (addr)-> {addr: addr, proccesingMethod: sensors.get('proccesingMethod')}
      countDev = Number(count)
      ports = JSON.parse JSON.stringify addrs
      device = devices.getByUid(id)
      deviceId = device.get('id')


      device
      .cmdSetPortsSetting
          done: (status, data)=>
            send deviceId, 'start', {count: Number(count), delay: Number(getDelay), addrs: ports},
              done: (status, data)=>
                @hatch[deviceId] = setInterval ()=>
                  send deviceId, 'get-values', {addrs: ports},
                    done: (status, data)=>
                      if Array.isArray(data.values)
                        rows = data.values.map (values)=>
                          # Обработка элементов
                          # ...
                          return row
                        # Запись результатов
                        # ...
                        countDev -= rows.length
                        if countDev <= 0
                          clearInterval(@hatch[deviceId])
                          cb?.done?()
                    fail: (err)->
                      clearInterval(@hatch[deviceId])
                      console.error(err)
                      cb?.fail?(err)
                , Number(updateDelay) * 1000
              fail: (err) ->
                console.error(err)
                cb?.fail?(err)
          fail: (err)->
            console.error(err)
            cb?.fail?(err)
  stop: ->
    for id, tHandler of @hatch
      clearInterval tHandler

  haveSensor: -> Object.keys(@devices).length > 0


class Model.Device extends Model.MongooseModel

  defaults:
    uid: ''
    title: 'Контроллер'
    verification: ''
    haveupdate: false
    protocol: ''
    version: ''

  portMap: null

  initialize: ->
    @portMap =
    {
      '1': 's0',
      '2': 's1',
      '3': 's2',
      '4': 's3'
    }

  getSensorByAddr: (addr)-> Model.Sensors.instance().getByUid(@portMap[addr])

  restore: ->
    @portMap =
    {
      '1': 's0',
      '2': 's1',
      '3': 's2',
      '4': 's3'
    }

  setPortsSetting: (index, id)->
    @portMap[String(index)] = id

  cmdUpdate: (cb)->
    send @get('id'), 'update', {},
      done: (status, data)->
        cb?.done?(status, data)
      fail: (err)->
        cb?.fail?(err)

  cmdSetPortsSetting: (cb)=>
    sensors = Model.Sensors.instance()
    params = []

    for addr, uid of @portMap
      params.push {addr, proccesingMethod: sensors.getByUid(uid).get('proccesingMethod')}

    send @get('id'), 'set-ports-setting', params,
      done: (status, data)->
        cb.done?(status, data)
      fail: (err)->
        cb.fail?(err)


class Model.Devices extends Model.MongooseCollection
  model: Model.Device

  initialize: ->
    super
    socket = io.connect()
    socket.on 'change', @wsChange
    socket.on 'update', @wsUpdate
    socket.on 'remove', @wsRemove
    socket.on 'add', @wsAdd

  @instance: ->
    unless Model.Devices._instance? then Model.Devices._instance = new Model.Devices
    return Model.Devices._instance

  getByUid: (uid)->
    return @find({uid})

  wsUpdate: (devices)=>
    # Обновление устройств
    # ...


  wsChange: (id, data, msg)=>
    # Изменение статуса устройства
    # ...

  wsRemove: (id, msg)=>
    # Удаление устройства
    # ...

  wsAdd: (id, data, msg)=>
    # Добавление устройства
    # ...
