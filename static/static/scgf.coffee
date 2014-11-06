# utility ###################################################

patch_list = (op, handler, item)->
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

$.fn.velocity_clean = (config, time, callback)->
	@velocity config, time, =>
		@removeAttr 'style'
		callback()

$.fn.velocity_in = (config, time, callback)->
	for key of config
		config[key] = [$(this).css(key), "easeInSine", 0]
	@velocity_clean config, time, callback

assignPlace = (place)->
	return false if not place
	return false if place[0] is '#'
	return true

fireProjectile = (projectile, from, to)->
	console.log projectile
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
	on : (name, func)->
		@[name] = @[name] or []
		@[name].push func
		return
	fire : (name, data)->
		console.log 'event: ' + name
		console.log data
		for func in (@[name] or [])
			func.call(null, data)
		return

eventBus = new EventBus()

# angular #############################################

angular.module 'scgf', ['ngAnimate']
	.controller 'gameController', ['$scope', '$templateCache', ($scope, $templateCache)->
		$scope.game_cover = ''
		$scope.game_list = []
		$scope.options = {}
		$scope.config = {}
		$scope.roomlist = []

		$scope.$root.roomlist = ->
			$scope.roomlist

		eventBus.on 'list', (data)->
			$scope.roomlist = data
			$scope.$apply()
		eventBus.on 'room', (data)->
			assets = window.assets
			if data.asset
				console.log 'load ' + data.asset
				assets.load data.asset, $templateCache
			if data.manifest
				$scope.current = data.manifest
				$scope.selected = data.manifest
				assets.onloaded ->
					$scope.game_cover = assets.text 'cover_img'
					$scope.game_description = assets.text '>desc'
					$scope.$apply()
				$.jGrowl '当前游戏：' + data.manifest
			if data.config
				$scope.options = data.options
				$scope.config = data.config
				for key of data.config
					continue if $scope.options[key] isnt undefined
					$scope.options[key] = data.config[key][0]
			if data.gamelist
				$scope.game_list = data.gamelist
			$scope.$apply()

		$scope.select = (thing)-> $scope.selected = thing
		$scope.load   = ->
			selected = $scope.selected
			return if not selected
			window.session.act 'game', 'setup', selected, $scope.options
		return
		]
	.controller 'roomController', ['$scope', '$sce', ($scope,$sce)->
		$scope.avatars = []
		$scope.players = []
		$scope.self = {}
		$scope.logs = []

		$scope.$root.onJoin = ->
			$scope.avatars = []
			$scope.players = []
			$scope.self = {}
			$scope.logs = []
		$scope.$root.players = ->
			$scope.players
		$scope.$root.logs = ->
			$scope.logs

		eventBus.on 'room', (data)->
			$scope.avatars = data.avatars
			$scope.$apply()
		eventBus.on 'avatar', (data)->

			sanitize = (id,data)->
				id : id
				avatar : data.avatar or 'none'
				role : data.group
				name : data.name
				score : data.score

			patch_list data.patch, 
				insert : (id, data)->
					$scope.players.push sanitize id,data
					if data.name is $scope.$parent.user
						$scope.self = $scope.players.last
					if data.name isnt 'anonymous'
						$.jGrowl data.name + '加入了游戏。'

				delete : (id)->
					for val,key in $scope.players
						if val.id is id
							$scope.players.splice(key,1)
							break
					if $scope.self.id is id
						$scope.self = {}
					else
						$.jGrowl val.name + '离开了游戏。'

				modify : (id, data)->
					for val,key in $scope.players
						if val.id is id
							if val.name is 'anonymous'
								if data.name isnt 'anonymous'
									$.jGrowl data.name + '加入了游戏。'
							old = $scope.players[key]
							$scope.players[key] = sanitize id,data
							$scope.players[key].current_score = data.score - old.score
							if data.name is $scope.$parent.user
								$scope.self = $scope.players[key]
							break
					
				, data
			$scope.$apply()
		eventBus.on 'log', (data)->
			if typeof data == 'string'
				$scope.logs.push $sce.trustAsHtml data
				$scope.$apply()
				body = $('#info .ui.logs')
				body.scrollTop body[0].scrollHeight
			else
				window.assets.onloaded ->
					assets = window.assets
					[label, clazz] = data.type.split '.'
					hint  = assets.text 'logs>text>'+label
					label = assets.text 'logs>label>'+label
					data.vars = assets.deref data.vars
					data.vars.hint = hint.format assets.deref data.vars
					data.vars.label = label.format data.vars
					data.vars.clazz = clazz

					log = window.assets.template 'log_entry', data.vars
					$scope.logs.push $sce.trustAsHtml log
					$scope.$apply()
					body = $('#info .ui.logs')
					body.scrollTop body[0].scrollHeight

		change_avatar_role = (avatar, role)->
			return if not $scope.self.name # doesn't exist
			avatar = avatar or $scope.self.avatar
			role = role or $scope.self.role
			window.session.act 'avatar', avatar, role

		$scope.select = (thing)-> 
			change_avatar_role null, thing
			#$scope.self.role = thing
		$scope.select_avatar = (guy)-> 
			#$scope.self.avatar = guy
			change_avatar_role guy, null
		return
		]
	.controller 'chatController', ['$scope','$sce', ($scope,$sce)->
		$scope.chats = []

		eventBus.on 'chat', (data)->
			$scope.chats.push $sce.trustAsHtml data
			$scope.$apply()
			$.jGrowl data
			body = $('.hover.message')
			body.scrollTop body[0].scrollHeight
		return
		]
	.controller 'containerController', ['$scope','$sce', ($scope,$sce)->
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

		setLayout = (layout)->
			$scope.layout = layout
			$scope.cards.top = {}
			$scope.cards.top[key] = [] for key in layout[0]
			$scope.cards.front = {}
			$scope.cards.front[key] = [] for key in layout[1]
			$scope.cards.back = {}
			$scope.cards.back[key] = [] for key in layout[2]
			$scope.cards.bottom = {}
			$scope.cards.bottom[key] = [] for key in layout[3]

		area = (place)->
			[row, col] = place.split '.'
			row_obj = $scope.cards[row] = $scope.cards[row] or {}
			row_obj[col] = row_obj[col] or []
			return row_obj[col]

		handle_game = (data)->
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
					place = area data.place
					place.push data
					old_place = area old.place
					old_place.remove old
				else
					place = area data.place
					place.push data
			else
				if assignPlace old.place
					old.to = data.place
					old_place = area old.place
					old_place.remove old
				else if data.place and data.from
					projectile = $ window.assets.template_angular data.template, data
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

		eventBus.on 'snapshot', (data)->
			$scope.cards = {}
			$scope.cards_lookup = {}
			$scope.asked = []
			$scope.selected = []
			$scope.selected_lookup = {}
			setLayout data.layout
			window.assets.onloaded ->
				for view in data.view
					handle_game view
				$scope.updateFilter()
				$scope.$apply()
			$scope.$apply()
		eventBus.on 'game', (data)->
			window.assets.onloaded ->
				handle_game data
				$scope.updateFilter()
				$scope.$apply()
			return

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
		]
	.controller 'sessionController', ['$scope', ($scope)->
		parent = $scope.$parent
		parent.user = window.session.nickname
		parent.room = window.session.room
		parent.connect = ->
			session = window.session
			if session.room isnt parent.room then parent.onJoin()
			session.act 'room', parent.room, parent.user
		]
	.animation '.cardframe', ->
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
					{ left, top } = dom.distanceTo tgt
					width_to = dom.width()
					dom.css 'width', 0
					dom.offset tgt.offset()
					dom.velocity_clean
						left: 0
						top: 0
						width: [width_to, "easeInSine", 0]
						, 800, -> done()
					return
			
			dom.velocity_clean
				opacity: [1, "easeInSine", 0]
				width: [dom.width(), "easeInSine", 0]
				, 300, -> done()
			return
		leave: (dom,done)->
			dom.find('[title]').popup 'remove'
			card = dom.scope().card
			console.log card
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
			dom.velocity_in
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

# assets ####################################################

#built-in

assets_common = 
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
		return if url == @assets_url
		@assets_url = url
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

				console.log $templateCache
				task() for task in @tasks
				@tasks = []

	text: (key)->
		result = @parsed.find('>text ' + key).text() if @parsed
		return result if result
		if assets_common[key] then return assets_common[key]
		return ''

	function: (key)->
		return @fn[key.toUpperCase()]

	deref: (vars)->
		for key, avar of vars
			continue if typeof avar isnt 'string'
			if avar[0] == '@'
				vars[key] = @text avar.slice(1)
		return vars

	template_angular: (key, vars)->
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
			$('#tab_room #room').val(@room)
			$('#tab_room #username').val(@nickname)

	saveCache: ->
		if @localStorage
			@localStorage.nickname = @nickname
			@localStorage.room = @room

	connect: (@room, @nickname)->
		@primus = new Primus()
		@primus.on 'open', =>
			$.jGrowl '服务器已连接。'
			@primus.write
				action : 'room'
				to : @room
				as : @nickname
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

	action_chat: (text)->
			text : text

	action_room: (newroom, @nickname)->
		if not @primus
			@nickname = @nickname or '陌生人'
			@room = newroom or @room or 'game_hall'
			@connect @room, @nickname
			console.log @room + ',' + @nickname
			@saveCache()
			return

		@nickname = @nickname or '陌生人'
		sent = { as : @nickname }
		if newroom != @room and newroom
			sent.from = @room if @room
			sent.to = newroom 
			@room = newroom
		console.log sent
		@saveCache()
		return sent

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
@session.connect @session.room, @session.nickname