_ = require 'lodash'
Loader = require 'scgf'
fs = require 'fs'
logger = require './logger'

listGames = ->
	fs.readdirSync('../games/').filter (file)->
		fs.statSync('../games/' + file).isDirectory()

cachedGameList = listGames()
module = @

safe = (func)->
	try
		return func()
	catch e
		logger.err e
	return

class RoomPlayer
	constructor: (@spark,@room)->
		@id = @spark.id
		@avatar = null
		@group = 'watcher'
		@nickname = 'anonymous'
		@score = 0
	notify: ->
		@spark.scgf_room @room, 'avatar', 'm' , 
			@id, @nickname, @avatar, @group, @score

class RoomPlayerCatalog
	constructor: ->
		@all = []
	add: (spark)->
		@all.push new RoomPlayer(spark, @room)
	remove: (spark)->
		_.remove @all, (one)->one.id is spark.id
	bySpark: (spark)->
		_.find @all, (one)->one.id is spark.id
	byAvatar: (avatar)->
		_.filter @all, (one)->one.avatar is avatar
	controllerOf: (avatar)->
		_.find @all, (one)->
			one.avatar is avatar and one.group is 'controller'
	filterAvatar: (avatar, callback)->
		for p in @all
			if avatar and p.avatar isnt avatar
				continue
			callback(p)

class RoomGameLogger
	constructor: (@room)->
	log : (type, vars)->
		if not type # just print a '' for linebreak
			for each in @room.players.all
				each.spark.scgf 'log',''
			return
		if not vars # print log as-is
			for each in @room.players.all
				each.spark.scgf 'log', type
			return
		for each in @room.players.all
			each.spark.scgf 'log',
				type : type
				vars : vars
	score : (scores)->
		for each in @room.players.all
			continue if each.group isnt 'controller'
			each.score += scores[each.avatar] or 0
			each.notify()
	finish : ->
		_.defer =>
			@room.setup(@room.game.gamecode, @room.options)

class RoomAvatarAssigner
	constructor: (@room)->
	assignAvatar: (player)->
		return false if player.avatar
		pool = []
		for avatar of @room.getAvatars()
			if not @room.players.controllerOf avatar
				pool.push avatar
		return false if not pool.length
		avatar = pool[Math.floor(Math.random() * pool.length)]
		@assignAvatarAs player, avatar, 'controller'
		return true
	assignAvatarAs: (player, avatar, group)->
		player.group = group
		player.avatar = avatar
		player.notify()
	reset: ->
		for p in @room.players.all
			p.avatar = null
			p.group = 'watcher'
			p.notify()

class RoomRenderer
	constructor: (@room)->
	getDesc: ->
		if not @room.game then return{
			manifest : 'None'
			options : {}
			gamelist : cachedGameList
			avatars : []
		}
		return{
			manifest : @room.game.gamecode
			options : @room.options
			config : @room.game.module.config()
			gamelist : cachedGameList
			avatars : _.keys @room.getAvatars()
			asset : '/' + @room.game.gamecode + 
				'/' + @room.game.gamecode + '.html'
		}
	getSnapshot: (one)->
		return if not @room.game
		entity = @room.entity one.avatar
		return if not entity
		return Loader.Viewer.snapshot @room.game, entity

class Room
	constructor: (@name)->
		@players = new RoomPlayerCatalog()
		@gamelogger = new RoomGameLogger(@)
		@assigner = new RoomAvatarAssigner(@)
		@renderer = new RoomRenderer(@)

	load: (gameName)->
		gamePath = '../games/' + gameName
		gameModule = gamePath + '/' + gameName + '.coffee'
		me = @
		safe ->
			module = require gameModule
			me.game = new Loader.Model.Game(gameName, module)

	getAvatars: (game)->
		if not @avatars and @game
			me = @
			safe ->
				me.avatars = me.game.module.avatars me.options
		return @avatars or {}

	registerWatcher: (avatar)->
		Loader.Viewer.watchby avatar, (type, evnt)=>
			@players.filterAvatar avatar.name, (one)->
				one.spark.write 
					event : type
					data : evnt

	entity: (avatar)->
		return if not avatar
		return if not @game
		return @game.root.select @getAvatars()[avatar]

	setup: (gameName, @options)->
		@game = @load(gameName)
		@avatars = undefined
		@game.setup @options
		@game.logger @gamelogger
		for avatar of @getAvatars()
			entity = @entity avatar
			@registerWatcher entity
		@game.start()

		for p in @players.all
			@assigner.assignAvatar p
		@updateDesc()
		@updateSnapshot()

	updateDesc: (player)->
		if player
			player.spark.scgf 'room', @renderer.getDesc()
			return
		for one in @players.all
			one.spark.scgf 'room', @renderer.getDesc()

	updateSnapshot: (player)->
		return if not @game
		if player
			snap = @renderer.getSnapshot player
			if snap
				player.spark.scgf 'snapshot', snap 
			else
				player.spark.scgf 'snapshot',
					layout : [[],[],[],[]]
					view : []
			return
		for one in @players.all
			snap = @renderer.getSnapshot one
			one.spark.scgf 'snapshot', snap if snap

games = {}

@getPlayer = (room, spark)->
	game = games[room]
	return if not game
	return game.players.bySpark spark

@listRooms = (spark) ->
	result = []
	for name of games
		room = games[name]
		result.push 
			name : name
			game : if room.game then room.game.gamecode else 'None'
			users : room.players.all.length
			playing : if room.game and room.game.ingame then true else false
	spark.scgf 'list', result

@enterRoom = (room, spark)->
	games[room] = new Room(room) if not games[room]
	game = games[room]
	game.players.add spark

	for him in game.players.all
		continue if him.id is spark.id
		spark.scgf 'avatar', 'i',
			him.id, him.nickname, him.avatar, him.group, him.score

	me = game.players.bySpark spark
	spark.scgf_room room, 'avatar', 'i', 
		me.id, me.nickname,	me.avatar, me.group, me.score

	game.updateDesc me
	game.assigner.assignAvatar me
	game.updateSnapshot me

@leaveRoom = (room, spark)->
	game = games[room]
	return if not game
	game.players.remove spark

	for one in game.players.all
		one.spark.scgf 'avatar', 'd', spark.id

	if _.isEmpty game.players.all
		delete games[room]

@setupRoom = (room, name, options)->
	return if not games[room]
	games[room].setup name, options

@setName = (room, spark, name)->
	return if not games[room]
	player = games[room].players.bySpark spark
	return if not player
	player.nickname = name
	player.notify()

@setAvatar = (room, spark, avatar, group)->
	game = games[room]
	return if not game
	players  = games[room].players
	player = players.bySpark spark
	return if not player

	running = game.game and game.game.ingame
	hasController = false
	players.filterAvatar avatar, (him)->
		if him.group is 'controller'
			hasController = true
	wasCandidate = true 
	wasCandidate = false if player.group is 'watcher'
	wasCandidate = false if player.avatar isnt avatar

	# before game starts : cannot select assigned avatar

	if group is 'controller'
		return if hasController
		return if running and not wasCandidate

	if group is 'candidate'
		return if running and not wasCandidate

	# in game : cannot select Candidate
	# only Candidate can be Controller if there isn't one

	game.assignAvatarAs player, avatar, group
	game.updateSnapshot player

@play = (room, spark, action, ids)->
	return if not games[room]

	g = games[room]
	player = g.players.bySpark spark
	role = player.group
	return if role is 'watcher'

	if role is 'candidate'
		c = g.players.controllerOf player.avatar
		return if c
	return if not g.game

	root = g.game.root
	avatar = g.entity player.avatar
	return if not avatar
	return if avatar.status != 'playing'

	entities = (root.select '&' + id for id in ids)
	avatar.targets[action] = entities
	avatar.status = 'played'
	if avatar.Viewable then avatar.Viewable.notify()
	g.game.resume()