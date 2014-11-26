# utility ###################################################

debounce = (func, wait)->
	timeout = null
	return ->
		me = @
		args = arguments
		dowork = ->
			timeout = null
			func.apply me, args
		clearTimeout timeout
		timeout = setTimeout dowork, wait

defer = (func)->
	setTimeout func(), 1

patchList = (op, handler, item)->
		code = op[0]
		id = op.slice(1)
		switch code
			when 'i' then handler.insert id, item
			when 'd' then handler.delete id, item
			when 'm'
				if handler.modify
					handler.modify id, item 
				else
					handler.delete id, item
					handler.insert id, item

String.prototype.format = String.prototype.format or (data)->
	@replace /{{(\w+)}}/g, (match, key)->
		if data.hasOwnProperty key then data[key] else match

Array.prototype.remove = Array.prototype.remove or (one)->
	i = @indexOf one
	return @ if i < 0
	@splice i, 1
	return @

Object.defineProperty Array.prototype, 'last', 
	get : -> @[@length-1]

Array.prototype.firstlike = (filter)->
	for each in this
		for key of filter
			return each if each[key] is filter[key]
	return undefined

$.fn.distanceTo = (thing)->
	left : thing.offset().left - @offset().left
	top : thing.offset().top - @offset().top

$.fn.velocityClean = (config, time, callback)->
	@velocity config, time, =>
		for key of config
			@css key, ''
		callback()

$.fn.velocityIn = (config, time, callback)->
	for key of config
		config[key] = [$(this).css(key), "easeInSine", 0]
	@velocityClean config, time, callback

assignPlace = (place)->
	return false if not place
	return false if place[0] is '#'
	return true

fireProjectile = (projectile, from, to)->
	return if not from.length or not to.length
	projectile.addClass 'absolute'
	projectile.css 
		'z-level': 1000
		top: 0
		left:0
	$('#container').append projectile

	start = projectile.distanceTo from
	stop  = projectile.distanceTo to

	projectile.offset from.offset()
	projectile.velocity
		opacity : [1, "easeInSine", 0]
	projectile.velocity 
		left : stop.left
		top : stop.top
	projectile.velocity
		opacity : 0
	, 300, ->projectile.remove()

window.fireProjectile = fireProjectile

class EventBus
	constructor: ->
		@scopes = {}
	scope : (name, scope)->
		@scopes[name] = scope
		scope['$digest'] = debounce ->
			scope.scope.$digest()
		, 100
	on : (name, scope, func)->
		@[name] = @[name] or {}
		@[name][scope] = @[name][scope] or []
		@[name][scope].push func
		return
	fire : (name, data)->
		# console.log 'event: ' + name, data
		for scope of @[name]
			for func in (@[name][scope] or [])
				func.call(@scopes[scope], data)
		return
	fireAsync : (name, data)->
		setTimeout =>
			@fire(name, data)
		, 1

eventBus = new EventBus()
window.eventBus = eventBus

# angular #############################################

# modals and main - root scope
#    roomlist, players, session, logs

# game sidebar - game scope
#    game list, current game, configs, options

# room sidebar - room scope
#    current player, avatars

# chat - chat scope
#    chats

# container - container scope
#    buttons, cards, chosen

scgf = angular.module 'scgf', ['ngAnimate']
	
scgf.controller 'scgfController', ['$scope', '$sce', ($scope, $sce)->
	eventBus.scope 'scgfController', 
		scope : $scope
		sce : $sce
	$scope.roomlist = []
	$scope.players = []
	$scope.logs = []
	$scope.session = {
		user : window.session.nickname
		room : window.session.room
	}

	$scope.resetSession = ->
		$scope.roomlist.length = 0
		$scope.players.length = 0
		$scope.logs.length = 0

	$scope.connectedSession = ->
		user : window.session.nickname
		room : window.session.room

	$scope.connect = ->
		session = window.session
		info = $scope.session
		if session.room isnt info.room then $scope.resetSession()
		session.act 'room', info.room, info.user
]

scgf.controller 'gameController', ['$scope', '$templateCache', ($scope, $templateCache)->
	eventBus.scope 'gameController', 
		scope : $scope
		templateCache : $templateCache
	$scope.gameCover = ''
	$scope.gamelist = []
	$scope.options = {}
	$scope.config = {}
	$scope.selected = ''
	$scope.current = ''

	$scope.resetGames = ->
		$scope.gameCover = ''
		$scope.gamelist.length = 0
		$scope.options = {}
		$scope.config = {}
		$scope.selected = ''
		$scope.current = ''

	$scope.select = (thing)-> $scope.selected = thing
	$scope.load = ->
		return if not $scope.selected
		window.session.act 'game', 'setup', $scope.selected, $scope.options
]

scgf.controller 'roomController', ['$scope', '$sce', ($scope,$sce)->
	eventBus.scope 'roomController', 
		scope : $scope
		sce : $sce
	$scope.avatars = []
	$scope.self = {}

	$scope.resetAvatar = ->
		$scope.avatars = []
		$scope.self = {}

	changeAvatarRole = (avatar, role)->
		return if not $scope.self.name # doesn't exist
		avatar = avatar or $scope.self.avatar
		role = role or $scope.self.role
		window.session.act 'avatar', avatar, role

	$scope.select = (thing)-> changeAvatarRole null, thing
	$scope.selectAvatar = (guy)-> changeAvatarRole guy, null
]

scgf.controller 'chatController', ['$scope','$sce', ($scope,$sce)->
	eventBus.scope 'chatController', 
		scope : $scope
		sce : $sce
	$scope.chats = []
]

scgf.controller 'containerController', ['$scope','$sce', ($scope,$sce)->
	eventBus.scope 'containerController', 
		scope : $scope
		sce : $sce
	# card hierarchy, with id lookup
	$scope.cards = {}
	$scope.cards_lookup = {}
	# button list, with enabled lookup
	$scope.asked = []
	$scope.asked_lookup = {}
	# selected list, with id lookup
	$scope.selected = []
	$scope.selected_lookup = {}

	$scope.layout = [[],[],[],[]]

	$scope.setLayout = (layout)->
		$scope.layout = layout
		$scope.cards.top = {}
		$scope.cards.top[key] = [] for key in layout[0]
		$scope.cards.front = {}
		$scope.cards.front[key] = [] for key in layout[1]
		$scope.cards.back = {}
		$scope.cards.back[key] = [] for key in layout[2]
		$scope.cards.bottom = {}
		$scope.cards.bottom[key] = [] for key in layout[3]

		$scope.asked = []

	$scope.subarea = (place)->
		[row, col] = place.split '.'
		row_obj = $scope.cards[row] = $scope.cards[row] or {}
		row_obj[col] = row_obj[col] or []
		return row_obj[col]

	$scope.handleGame = (data)->
		id = data.id
		window.assets.deref data
		old = $scope.cards_lookup[id] or {}
		$scope.cards_lookup[id] = data

		# if data has place
			# if old has same place -> replace
			# if old has place -> remove old, add new
			# if old has no place or there is no old -> add new
		# if data has no place
			# if old has place -> remove old
			# if old has no place or there is no old -> do nothing

		if assignPlace data.place
			if old.place is data.place
				old[key] = data[key] for key of data
				$scope.cards_lookup[id] = old
			else if assignPlace old.place
				place = $scope.subarea data.place
				place.push data
				old_place = $scope.subarea old.place
				old_place.remove old
			else
				place = $scope.subarea data.place
				place.push data
		else
			if assignPlace old.place
				old.to = data.place
				old_place = $scope.subarea old.place
				old_place.remove old
			else if data.place and data.from
				projectile = $ window.assets.templateAngular data.template, data
				fireProjectile projectile, $('.cardframe.'+data.from.slice(1)), 
					$('.cardframe.'+data.place.slice(1)) 

		if data.asked 
			$scope.asked = data.asked
			if data.asked[0] == 'next_game'
				window.setTimeout ->
					$('.modal#result').modal('show')
				, 1000
			$scope.selected = []
			$scope.selected_lookup = {}
			if data.asked.length 
				window.document.title = '该你了！ - SCGF'
				window.focus()
			else window.document.title = 'SCGF'

	$scope.updateFilter = ->
		access = $scope.cards
		selected = $scope.selected

		for ask in $scope.asked
			fn = window.assets.function ask
			b = fn.call(null, access, selected)
			$scope.asked_lookup[ask] = b

		for row of access
			for column of access[row]
				for toselect in access[row][column]
					if $scope.isSelected toselect
						toselect.enabled = true
						continue
					else 
						toselect.enabled = false

					for ask in $scope.asked
						fn = window.assets.function ask
						b = fn.call(null, access, selected, toselect)
						toselect.enabled = toselect.enabled or b
		return
	$scope.select = (one)->
		return if not one.enabled
		if $scope.isSelected one
			$scope.selected.remove one
			delete $scope.selected_lookup[one.id]
		else
			$scope.selected.push one
			$scope.selected_lookup[one.id] = one
		$scope.updateFilter()
	$scope.isSelected = (one)->
		$scope.selected_lookup[one.id]
	$scope.submit = (ask)->
		return if not $scope.asked_lookup[ask]
		window.session.act 'play', ask, $scope.selected
		$scope.asked_lookup[ask] = false for ask in $scope.asked
		return
	$scope.maxWidth = (card,$last)->
		return '1000px' if $last
		[row, col] = card.place.split '.'
		row_obj = $scope.cards[row]
		col_obj = row_obj[col]
		return '1000px' if col_obj.length <= 1
		cols = 0
		for acol of row_obj 
			cols += 1
		available = window.windowWidth - 260 - 90 * cols
		return (available / (col_obj.length - 1))+ 'px'
]

# events handling #################################################################

eventBus.on 'list','scgfController', (data)->
	@scope.roomlist = data
	@$digest()

eventBus.on 'room', 'gameController', (data)->
	assets = window.assets
	if data.asset
		console.log 'loading ' + data.asset
		assets.load data.asset, @templateCache
	if data.manifest
		@scope.current = data.manifest
		for agame in data.gamelist or []
			if agame is data.manifest
				@scope.selected = agame
				break
		assets.onloaded =>
			@scope.gameCover = assets.text 'cover_img'
			@scope.gameDesc = assets.text '>desc'
			@$digest()
		$.jGrowl '当前游戏：' + data.manifest
	if data.config
		@scope.options = data.options
		@scope.config = data.config
		for key of data.config
			continue if @scope.options[key] isnt undefined
			@scope.options[key] = data.config[key][0]
	if data.gamelist
		@scope.gamelist = data.gamelist
	@$digest()

eventBus.on 'room', 'roomController', (data)->
	@scope.avatars = data.avatars
	@$digest()

eventBus.on 'avatar', 'scgfController', (data)->

	sanitize = (obj, id, data)->
				obj.id = id
				obj.avatar = data.avatar or 'none'
				obj.role = data.group
				obj.name = data.name
				obj.score = data.score
				return obj

	patchList data.patch,
		insert : (id, data)=>
			@scope.players.push sanitize {},id,data
			if data.name isnt 'anonymous'
				$.jGrowl data.name + '加入了游戏。'

		delete : (id)=>
			for val,key in @scope.players
				if val.id is id
					@scope.players.splice(key,1)
					break
				$.jGrowl val.name + '离开了游戏。'

		modify : (id, data)=>
			for val in @scope.players
				if val.id is id then break

			if val.id isnt id 
				console.error 'what? didnt find player to update'
				return

			if val.name is 'anonymous'
				if data.name isnt 'anonymous'
					$.jGrowl data.name + '加入了游戏。'
			
			val.current_score = data.score - val.score
			sanitize val,id,data
	, data

	@$digest()

eventBus.on 'avatar', 'roomController', (data)->
	op = data.patch[0]
	return if op is 'd' and @scope.self.id isnt data.patch.slice(1)
	return if data.name and data.name isnt @scope.session.user

	@scope.self = {}
	for one in @scope.players
		if one.name is data.name
			@scope.self = one
			@$digest()
			return

eventBus.on 'log', 'scgfController', (data)->
	if typeof data is 'string'
		@scope.logs.push @sce.trustAsHtml data
		@$digest()
		body = $('#info .ui.logs')
		body.scrollTop body[0].scrollHeight
	else
		window.assets.onloaded =>
			assets = window.assets
			[label, clazz] = data.type.split '.'
			hint  = assets.text 'logs>text>'+label
			label = assets.text 'logs>label>'+label
			data.vars = assets.deref data.vars
			data.vars.hint = hint.format assets.deref data.vars
			data.vars.label = label.format data.vars
			data.vars.clazz = clazz
			log = window.assets.template 'log_entry', data.vars

			@scope.logs.push @sce.trustAsHtml log
			@$digest()
			body = $('#info .ui.logs')
			body.scrollTop body[0].scrollHeight


eventBus.on 'chat','chatController', (data)->
	@scope.chats.push @sce.trustAsHtml data
	@$digest()
	$.jGrowl data
	body = $('.hover.message')
	body.scrollTop body[0].scrollHeight

eventBus.on 'snapshot', 'containerController', (data)->
	@scope.cards = {}
	@scope.cards_lookup = {}
	@scope.asked = []
	@scope.selected = []
	@scope.selected_lookup = {}
	@scope.setLayout data.layout
	window.assets.onloaded =>
		for view in data.view
			@scope.handleGame view
		@scope.updateFilter()
		@$digest()
	@$digest()

eventBus.on 'game', 'containerController', (data)->
	window.assets.onloaded =>
		@scope.handleGame data
		@scope.updateFilter()
		@$digest()
	return

eventBus.on 'connected', 'scgfController', ->
	@scope.resetSession()
eventBus.on 'connected', 'gameController', ->
	@scope.resetGames()
eventBus.on 'connected', 'roomController', ->
	@scope.resetAvatar()
eventBus.on 'connected', 'containerController', ->
	eventBus.fire 'snapshot', 
		layout: [[],[],[],[]]
		view: []
eventBus.on 'connected', 'chatController', ->
	@scope.chats.length = 0

# animation ##################################################

scgf.animation '.cardframe', ->
	enter: (dom, done)->
		dom.find('[title]').popup()
		card = dom.scope().card
		if card.from
			if assignPlace card.from
				from = card.id
			else
				from = card.from.slice(1)
			tgt = $('.cardframe.'+from).not(dom)
			if tgt.length
				width_to = dom.width()
				dom.css 'width', 0
				{ left, top } = dom.distanceTo tgt
				dom.css 
					left: left
					top: top
				dom.velocityClean
					left: 0
					top: 0
					width: [width_to, "easeInSine", 0]
					, 800, -> done()
				return
		
		dom.velocityClean
			opacity: [1, "easeInSine", 0]
			width: [dom.width(), "easeInSine", 0]
			, 300, -> done()
		return
	leave: (dom,done)->
		dom.find('[title]').popup 'remove'
		card = dom.scope().card
		if card.to and not assignPlace(card.to)
			to = card.to.slice(1)
			tgt = $('.cardframe.'+to)
			if tgt.length
				{ left, top } = $(dom).distanceTo tgt
				dom.velocity
					left: [left, "easeInSine", 0]
					top: [top, "easeInSine", 0]
					opacity : [0 ,"easeInSine", 1]
					width: 0
					, 800, -> done()			
				return

		dom.css 'opacity', 0
		dom.velocity
			width : 0
			, 300, -> done()
		return
.animation '.playbutton', ->
	enter: (dom,done)->
		dom.popup()
		dom.css 'overflow-x','hidden'
		dom.velocityIn
			width: true
			'padding-left': true
			'padding-right': true
		, 300, ->done()
		return
	leave: (dom,done)->
		dom.popup 'remove'
		dom.css 'overflow-x','hidden'
		dom.velocity
			width: 0
			'padding-left': 0
			'padding-right': 0
		, 300, ->done()
		return
.filter 'lookup', ->
	(input)->
		result = window.assets.text input
		return result if result
		return input
.filter 'whosbehind', ->
	(input, $scope)->
		for p in $scope.players
			aname = window.assets.text p.avatar
			if aname is input and p.role is 'controller'
				return p.name
		return input
.filter 'iconof', ->
	(input)-> 
		switch input
			when 'playing' then return 'red loading'
			when 'played' then return 'green checkmark'
			else return 'green user'

# assets ####################################################

#built-in

assetsCommon = 
	'nogame' : '无游戏'
	'candidate' : '替补'
	'watcher' : '观战'
	'controller' : '控制'
	'desc' : '当前未载入游戏'
	'cover_img' : ''
	'avatar>none' : '无角色'
	'cardarea>player' : '玩家'
	'cardarea>hand' : '手牌'
	'cardarea>draw' : '牌堆'
	'playtip>play>next_game' : '新游戏'
	'playtip>play>ready' : '准备'
	'playtip>hint>next_game' : '所有玩家确认后，开始一局新的游戏。'
	'playtip>hint>ready' : '游戏在所有玩家都准备后开始。'

class Assets
	constructor: ->
		@fn = {
			READY : (a, s, t)->not t
			NEXT_GAME : (a, s, t)->not t
		}
		@tasks = []
	load: (url,$templateCache)->
		return if url == @assetsUrl
		@assetsUrl = url
		@parsed = undefined
		console.log 'loading assets...'
		$.ajax
			url : url
			success : (data)=>
				@parsed = $($.parseHTML data)
				console.log 'assets loaded!'

				css = @parsed.find '>style'
				if css.length > 0
					$('head').append css

				js = @parsed.find '>js'
				fn = @fn
				if js.length > 0
					js.children().each ->
						key = $(@).prop('tagName')
						console.log 'loading function ' + key
						# console.log $(@).text()
						fn[key] = eval ( $(@).text() )

				if $templateCache
					for each in @parsed.find('>templates').children()
						name = each.tagName.toLowerCase()
						html = each.innerHTML
						$templateCache.put name, html

				task() for task in @tasks
				@tasks = []

	text: (key)->
		result = @parsed.find('>text ' + key).text() if @parsed
		return result if result
		if assetsCommon[key] then return assetsCommon[key]
		return ''

	function: (key)->
		return @fn[key.toUpperCase()]

	deref: (vars)->
		for key, avar of vars
			continue if typeof avar isnt 'string'
			if avar[0] == '@'
				vars[key] = @text avar.slice(1)
		return vars

	templateAngular: (key, vars)->
		str = @parsed.find('>templates>' + key).html();
		vars = @deref vars
		str = str.replace /card\./g,''
		str = str.replace /ng-src/g,'src'
		return str.format vars

	template: (key, vars)->
		str = @parsed.find('>templates>' + key).html();
		vars = @deref vars
		return str.format vars

	onloaded: ( task )->
		if @parsed
			task()
			return
		@tasks.push task

@assets = new Assets()

# protocol ###################################################

class Session
	constructor:->
		@localStorage = window.localStorage
		@loadCache()
	loadCache: ->
		if @localStorage
			@nickname = @localStorage.nickname or @nickname or '陌生人'
			@room = @localStorage.room or @room or 'game_hall'

	saveCache: (user, room)->
		if @localStorage
			@localStorage.nickname = user
			@localStorage.room = room

	connect: ->
		@primus = new Primus()
		@primus.on 'open', =>
			$.jGrowl '服务器已连接。'
			eventBus.fire 'connected'
			@joined = false
		@primus.on 'data', (msg)=>
			eventBus.fire msg.event, msg.data
		@primus.on 'reconnect', ->
			$.jGrowl '重新连接服务器……'

	act : (action, args...)->
		if @['action_' + action]
			sent = @['action_' + action].apply @,args
			return if not sent
			sent.action = action
			sent.room = @room
			@primus.write sent
			# console.log 'action: ' + action, sent

	action_chat: (text)->
			text : text

	action_room: (newroom, @nickname)->
		if not @primus
			console.error 'hey you should have inited primus!'

		@nickname = @nickname or '陌生人'
		newroom = newroom or @room
		
		if not @joined
			eventBus.fireAsync 'connected'
			@joined = true
			@room = newroom
			return {
				to : newroom
				as : @nickname
			}
		else if newroom is @room then return {
			as : @nickname
		} else
			oldroom = @room
			@room = newroom
			eventBus.fireAsync 'connected'
			return {
				from : oldroom
				to : newroom
				as : @nickname
			}
		@saveCache @nickname, @room

	action_avatar: (avatar, group)->
			avatar : avatar
			group : group

	action_play: (play, chosen)->
			play : play
			ids : one.id for one in chosen

	action_game: (op, game, config)->
			op : op
			game : game
			options : config

	action_list: ->{}


@session = new Session()
@session.connect()