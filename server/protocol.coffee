games = require './gamemanager'
logger = require './logger'

@extend = (prototype)->
	P = {}
	P.log = (msg)->
		event : 'log'
		data : msg

	P.chat = (speaker, msg)->
		event : 'chat'
		data : '<b>' + speaker + ': </b>' + msg

	P.room = (msg)->
		event : 'room'
		data : msg

	P.avatar = (op, id, name, avatar, group, score)->
		event : 'avatar'
		data :
			patch : op + id.replace '$', '_'
			name : name
			avatar : avatar
			group : group
			score : score

	P.game = (op, eid, row, column, view)->
		event : 'game'
		data :
			patch : op + eid
			row : row
			column : column
			view : view

	P.snapshot = (data)->
		event : 'snapshot'
		data : data

	P.player = (hint, filter_map)->
		event : 'player'
		data : 
			hint : hint
			filters : filter_map

	P.list = (result)->
		event : 'list'
		data : result

	prototype.scgf = (type, args...)->
		@write P[type].apply @, args

	prototype.scgf_room = (room, type, args...)->
		@room(room).write P[type].apply @, args

class Actions
	on: (spark, action, room, context)->
		return if not @[action]

		return @[action](spark, room, context)

	play: (spark, room, context)->
		logger.log 
			user: (games.getPlayer(room, spark) or {}).name
			context: context
			,'action_play'
		games.play room, spark, context.play, context.ids

	chat: (spark, room, context)->
		logger.log
			user: (games.getPlayer(room, spark) or {}).name
			text: context.text
			, 'action_chat'
		speaker = (games.getPlayer(room, spark) or {}).name
		spark.scgf_room room, 'chat', speaker, context.text

	game: (spark, room, context)->
		logger.log
			user: (games.getPlayer(room, spark) or {}).name
			context: context
		games.setupRoom room, context.game, context.options

	avatar: (spark, room, ctx)->
		logger.log 
			user: (games.getPlayer(room, spark) or {}).name
			context : ctx
			, 'action_avatar'
		games.setAvatar room, spark, ctx.avatar, ctx.group

	rename : (spark, room, name)->
		logger.log 
			spark : spark.id 
			room : room
			user : name
			, 'action_rename'
		games.setName room, spark, name

	list : (spark, room)->
		logger.log spark.id + ' asked for roomlist'
		games.listRooms spark

	join: (spark, room)->
		logger.log spark.id + ' joined room ' + room
		games.enterRoom room, spark

	leave: (spark, room, primus)->
		logger.log spark.id + ' left room ' + room
		games.leaveRoom room, spark

@actions = new Actions()