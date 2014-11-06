_ = require 'lodash'
Loader = require 'scgf'
fs = require 'fs'
logger = require './logger'

listGames = ->
	fs.readdirSync('../games/').filter (file)->
		fs.statSync('../games/' + file).isDirectory()

cachedGameList = listGames()
module = @

class RoomPlayer
	constructor: (@spark,@room)->
		@id = @spark.id
		@avatar = null
		@control_group = 'candidate'
		@nickname = 'anonymous'
		@score = 0
	notify: ->
		@spark.scgf_room @room, 'avatar', 'm' , 
			@id, @nickname, @avatar, @control_group, @score

class RoomPlayerCatalog
	constructor: (@room)->
		@by_id = {}
		@by_avatar = {}

	add : (spark)->
		player = new RoomPlayer spark, @room
		@by_id[player.id] = player
		@by_avatar[player.avatar] = {} if not @by_avatar[player.avatar]
		@by_avatar[player.avatar][player.id] = player

	remove : (spark)->
		player = @by_id[spark.id]
		delete @by_id[spark.id]
		delete @by_avatar[player.avatar][player.id]

	each : (fn)->
		fn.apply one, [one,key] for key,one of @by_id

	setName : (id, name)-> 
		player = @by_id[id]
		return if not player
		player.nickname = name 
		player.notify()
	getName : (id)-> (@by_id[id] or {}).nickname

	setGroup : (id, group)->
		player = @by_id[id]
		return if not player
		player.control_group = group
		player.notify()
	getGroup : (id)-> (@by_id[id] or {}).control_group

	setAvatar : (id, avatar)->
		player = @by_id[id]
		return if not player
		delete @by_avatar[player.avatar][player.id]
		player.avatar = avatar
		@by_avatar[player.avatar] = {} if not @by_avatar[player.avatar]
		@by_avatar[player.avatar][player.id] = player
		player.notify()
	getAvatar : (id)-> (@by_id[id] or {}).avatar

class Room
	constructor: (@name)->
		@players = new RoomPlayerCatalog(@name)

	assignAvatar: (player,skip)->
		return if player.avatar
		return if not @avatar_map
		for avatar of @avatar_map
			if _.isEmpty @players.by_avatar[avatar]
				logger.log 'assigned ' + player.id + ' as ' + avatar
				@assignAvatarAs player, avatar, 'controller',skip
				break;

	assignAvatarAs: (player, avatar, group,skip)->
		player.control_group = group
		@players.setAvatar player.id, avatar
		if not skip then @updateSnapshotFor player

	resetAvatars: ->
		@players.each (one)->
			one.avatar = null
			one.control_group = 'candidate'
			one.notify()

	updateDesc: ->
		@players.each (one)=>
			one.spark.scgf 'room', @getDesc()

	avatarEntity: (avatar)->
		return if not avatar
		return @game.root.select @avatar_map[avatar]

	updateSnapshot: ->
		return if not @game
		@players.each (one)=>
			@updateSnapshotFor(one)

	updateSnapshotFor: (one)->
		return if not @game
		entity = @avatarEntity one.avatar
		return if not entity
		snap = Loader.Viewer.snapshot @game, entity
		one.spark.scgf 'snapshot', snap

	setup: (gameName, @options)->

		flag_reassign = gameName != @gameName
		@gameName = gameName

		gamePath = '../games/' + @gameName
		gameModule = gamePath + '/' + @gameName + '.coffee'
		module = require gameModule
		@game = new Loader.Model.Game(@gameName, module)
		@avatar_map = @game.module.avatars @options
		@game.setup @options
		me = @
		@game.logger 
			log : (type, vars)->
				if not type # just print a '' for linebreak
					for id,each of me.players.by_id
						each.spark.scgf 'log',''
					return
				if not vars # print log as-is
					for id,each of me.players.by_id
						each.spark.scgf 'log', type
					return
				for id,each of me.players.by_id
					each.spark.scgf 'log',
						type : type
						vars : vars
			score : (scores)->
				for id,each of me.players.by_id
					each.score += scores[each.avatar] or 0
					each.notify()
			finish : ->
				_.defer ->
					me.setup(gameName, me.options)

		for avatar_name in _.values @avatar_map
			do(avatar_name)=>
				avatar = @game.root.select avatar_name
				Loader.Viewer.watchby avatar, (type, evnt)=>
					_.each @players.by_avatar[avatar.name], (one)->
						one.spark.write 
							event : type
							data : evnt

		if flag_reassign
			@resetAvatars()
			@players.each (one)->
				me.assignAvatar one,true

		@updateDesc()
		@updateSnapshot()
		@game.start()

		# TODO setup in-game view watch

	getDesc : ->
		if not @game then return{
			manifest : 'No game set'
			options : {}
			gamelist : cachedGameList
			avatars : []
		}
		return{
			manifest : @game.gamecode
			options : @options
			config : @game.module.config()
			gamelist : cachedGameList
			avatars : _.keys @avatar_map
			asset : '/' + @game.gamecode + '/' + @game.gamecode + '.html'
		}

games = {}

@listRooms = (spark) ->
	result = []
	for name of games
		room = games[name]
		result.push 
			name : name
			game : if room.game then room.game.gamecode else 'No game set'
			users : _.size room.players.by_id
			playing : if room.game and room.game.runner then true else false
	spark.scgf 'list', result

@enterRoom = (room, spark)->
	games[room] = new Room(room) if not games[room]
	games[room].players.add spark

	for client in spark.room(room).clients()
		continue if client == spark.id 
		him = games[room].players.by_id[client]
		spark.scgf 'avatar', 'i',
			him.id, him.nickname, him.avatar, him.control_group, him.score

	me = games[room].players.by_id[spark.id]
	spark.scgf_room room, 'avatar', 'i', 
		me.id, me.nickname,	me.avatar, me.control_group, me.score

	spark.scgf 'room', games[room].getDesc()
	games[room].assignAvatar(me)

@leaveRoom = (room, spark)->
	the_room = games[room]
	return if not the_room
	the_room.players.remove spark

	the_room.players.each (one)->
		one.spark.scgf 'avatar', 'd', spark.id

	if _.isEmpty the_room.players.by_id
		delete games[room]

@setupRoom = (room, name, options)->
	games[room].setup name, options

@setName = (room, spark, name)->
	games[room].players.setName spark.id, name

@setAvatar = (room, spark, avatar, group)->
	players  = games[room].players
	player = players.by_id[spark.id]
	games[room].assignAvatarAs(player, avatar, group)

@getName = (room, spark)->
	games[room].players.getName spark.id

@play = (room, sparkid, action, ids)->
	return if not games[room]
	g = games[room]
	root = g.game.root
	avatar = g.avatarEntity g.players.getAvatar sparkid

	return if not avatar
	return if avatar.status != 'playing'
	entities = (root.select '&' + id for id in ids)
	avatar.targets[action] = entities
	g.game.resume()