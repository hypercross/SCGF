# 导入依存库 ################################################
Loader = require('scgf')
Entity = Loader.Entity
Model = Loader.Model
GameEvent = Model.GameEvent
Listener = Model.Listener
_ = require('lodash')

# helper ####################################################

renderCardName = (s)->
	return s if typeof s is 'number'
	return '@card>name>'+s	

renderCardDesc = (s)->
	return '@card>desc>number' if typeof s is 'number'
	return '@card>desc>'+s	

# 游戏实体结构 ##############################################
class UnoPlayer extends Entity.Player
	init:->
		super()
		@hand 		= @.spawnChild Entity.CardSlot, 'hand'
		@.setComponent new Loader.Component.Viewable (viewpoint)=>
			asked : if viewpoint == @ then @getAsked() else undefined
			place : if viewpoint == @ then 'bottom.player' else 'top.player'
			template : 'player'
			status : if @getAsked().length then 'playing' else 'ready'
			name : '@' + @name
			hand : @hand.deck.length

	hasColor:(color)->
		_.find @hand.deck, (one)->one.color == color

class UnoCard extends Entity.Card
	stat:(@name,@color)->
	init:->
		super()
		@.setComponent new Loader.Component.Viewable (viewpoint)=>

			render_front = =>
				template : 'front_card'
				name : renderCardName @name
				color : '@color>' + @color
				hint : renderCardDesc @name

			render_back = ->
				template : 'cover_card'

			rendered = null
			if @parent() isnt viewpoint.hand
				if @parent().name isnt 'discarded'
					rendered = render_back()
				else 
					rendered = render_front()
				rendered.place = '#' + @parent().parent().id
			else
				rendered = render_front()
				rendered.place = 'bottom.hand'
			return rendered

	@type_property 'color'

class UnoDeck extends Entity.CardSlot
	init:->
		super()

		@draw = @spawnChild Entity.CardSlot, 'draw'
		@discarded = @spawnChild Entity.CardSlot, 'discarded'

		for color in ['red','blue','green','yellow']
			@draw.spawnChild(UnoCard).stat 0, color
			for rank in [1..9]
				@draw.spawnChild(UnoCard).stat(rank, color) for i in [1..2]
			@draw.spawnChild(UnoCard).stat('Skip', color) for i in [1..2]
			@draw.spawnChild(UnoCard).stat('DrawTwo', color) for i in [1..2]
			@draw.spawnChild(UnoCard).stat('Reverse', color) for i in [1..2]
		@draw.spawnChild(UnoCard).stat('Wild', 'wild') for i in [1..4]
		@draw.spawnChild(UnoCard).stat('WildFour', 'wild') for i in [1..4]
		@draw.shuffle()
		@.setComponent new Loader.Component.Viewable (viewpoint)=>
			place: 'front.draw'
			template : 'deck'
			draw : @draw.deck.length
			discard : @discarded.deck.length
			color : '@color>' + (@game().uno_state or {color:'wild'}).color
			symbol : @getViewedSymbol()
	getViewedSymbol:->
		symbol = (@game().uno_state or {name:'Wild'}).name
		return renderCardName symbol
	drawTo:(player,count)->
		count = count or 1
		if @draw.deck.length == 0
			temp = @draw
			@draw = @discarded
			@discarded = temp
			@draw.shuffle()
		while count
			card = @draw.deck.pop()
			card.Owned.by = null
			card.moveTo player.hand
			card.notify()
			count--
		player.notify()
		return card
	discard:(card)->
		if not card
			card = @draw.deck.pop()
			card.Owned.by = null
		card.moveTo @discarded
		card.notify()
		return card

# validation ################################################

match = (player, played, color, uno_state)->
	# playing a card from hand
	return false if not played
	return false if played.length != 1
	play = played[0]
	return false if player.hand != play.parent()

	# playing a matching card
	if play.color isnt 'wild'
		return false if play.color isnt uno_state.color and 
			play.name isnt uno_state.name
	else if play.name is 'WildFour'
		return false if player.hasColor uno_state.color

	# declaring valid color
	return true if play.color == 'wild'
	return true if uno_state.color == 'wild'
	return true if play.color == color

	return false

# 接口 ######################################################

NAMES = ['Alfred','Benedict','Carl','David','Eugene','Finch']

@config = ->
	playercount : [2,3,4,5,6]

@setup = (game, options)->
	players = {}
	for player in NAMES.slice(0,options.playercount or 2)
		players[player] = UnoPlayer
	Loader.spawnLayout game,
		players: players
		deck : UnoDeck

@layout = (options)->[
    ['player']
    ['draw']
    []
    ['player', 'hand']
]

@avatars = (options)->
	map = {}
	for player in NAMES.slice(0,options.playercount or 2)
		map[player] = '.' + player
	return map

# 流程 #####################################################

@run = (game)->
	players = game.root.select('.players').children()
	deck = game.root.select '.deck'
	logger = game.logger()
	# 游戏开始摸牌
	for player in players
		deck.drawTo(player,7)
	# 扔掉第一张牌
	card = deck.discard()
	# 游戏状态
	uno_state = game.uno_state = {
		direction : 1
		color : card.color
		name : card.name
	}
	deck.notify();
	current_player = players[Math.floor(Math.random() * players.length)]

	# 游戏开始	

	empty = (choice)-> return choice and choice.length == 0

	next = (player)->
		return player.Peer.next if uno_state.direction == 1
		return player.Peer.prev if uno_state.direction == -1
		return null

	while true
		logger.log current_player.name + ' asked to play'
		logger.log 'to match : ' + uno_state.color + 
			' ' + uno_state.name
		logger.log current_player.name + ' has:'
		logger.log _.reduce current_player.hand.deck, (sum,card)->
			sum += card.color + ' ' + card.name + ', '
		, ''

		# 接牌，或者摸牌
		current_player.asked
			as_yellow : (choice)->
				match(current_player, choice, 'yellow', uno_state)
			as_blue : (choice)->
				match(current_player, choice, 'blue', uno_state)
			as_red : (choice)->
				match(current_player, choice, 'red', uno_state)
			as_green : (choice)->
				match(current_player, choice, 'green', uno_state)
			draw : (choice)->empty(choice)
		current_player.collect()

		action = _.findKey current_player.targets, (one)->true
		chosen = current_player.targets[action]
		logger.log current_player.name + ' chose ' + action

		# 若选择摸牌
		if action is 'draw'
			# 摸牌
			card = deck.drawTo current_player
			deck.notify();
			logger.log current_player.name + ' drew ' +
				card.color + ' ' + card.name
			# 可选择立即使用
			current_player.asked
				as_yellow_empty : (choice)->
					match(current_player, [card], 'yellow', uno_state) and 
						empty(choice)
				as_blue_empty : (choice)->
					match(current_player, [card], 'blue', uno_state) and 
						empty(choice)
				as_red_empty : (choice)->
					match(current_player, [card], 'red', uno_state) and 
						empty(choice)
				as_green_empty : (choice)->
					match(current_player, [card], 'green', uno_state) and 
						empty(choice)
				keep : (choice)->empty(choice)
			current_player.collect()

			action = _.findKey current_player.targets, (one)->true
			chosen = current_player.targets[action]
			if action.slice(0,3) is 'as_' then chosen = [card]
			logger.log current_player.name + ' chose ' + action

		# 若使用牌
		if chosen and chosen.length > 0
			card = chosen[0]
			color_initial = action[3]
			switch color_initial
				when 'r' then uno_state.color = 'red'
				when 'g' then uno_state.color = 'green'
				when 'b' then uno_state.color = 'blue'
				when 'y' then uno_state.color = 'yellow'
			uno_state.name = card.name
			logger.log current_player.name + ' played ' + 
				card.name + ' ' + card.color
			deck.discard card
			current_player.notify()

			if current_player.hand.deck.length == 0
				logger.log current_player.name + ' has won the game.'
				score = _.reduce players, (sum, one)->
					sum+_.reduce one.hand.deck, (sum, one)->
						switch one.name
							when 'Reverse' then 20+sum
							when 'DrawTwo' then 20+sum
							when 'Skip' then 20+sum
							when 'Wild' then 50+sum
							when 'WildFour' then 50+sum
							else one.name+sum
					,0
				,0
				scores = {}
				scores[current_player.name] = score
				logger.score scores
				return

			uno_state.direction *= -1 if card.name == 'Reverse'

		current_player = next(current_player)

		if chosen and chosen.length > 0
			switch card.name
				when 'DrawTwo'
					deck.drawTo(current_player) for i in [1..2]
					current_player = next(current_player)
				when 'WildFour'
					deck.drawTo(current_player) for i in [1..4]
					current_player = next(current_player)
				when 'Skip'
					current_player = next(current_player)
			deck.notify();