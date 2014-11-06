Primus = require 'primus'
Rooms = require 'primus-rooms'
http = require 'http'
connect = require 'connect'
serve_static = require 'serve-static'
logger = require './logger'

######## server ###############################

connect_handler = connect()
	.use serve_static '../static'
	.use serve_static '../games'
server = http.createServer connect_handler

primus = new Primus server, 
	transformer: 'websockets'

primus.use 'rooms', Rooms

primus.save '../static/static/primus.js'

######## protocol ###############################

Protocol = require './protocol'
Protocol.extend primus.Spark.prototype

primus.on 'connection', (spark)->

	spark.on 'data', (data)->

		data = data or {}
		action = data.action

		return if not action

		if action == 'room'
			if data.from
				spark.leave data.from, ->
			if data.to
				spark.join data.to, ->
					if data.as
						Protocol.actions.on spark, 
						'rename', data.to, data.as
			else if data.as
				Protocol.actions.on spark, 
				'rename', data.room, data.as

		else Protocol.actions.on spark, action, data.room, data

	spark.on 'roomserror', (err)->
	  logger.log err

primus.on 'joinroom', (room, spark)->
	Protocol.actions.on spark, 'join', room

primus.on 'leaveallrooms', (rooms, spark)->
	for room in rooms
		spark.leave room,-> 

primus.on 'leaveroom', (room, spark)->
	Protocol.actions.on spark, 'leave', room, primus

server.listen 8192