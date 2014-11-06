# scgf 游戏实例 - Brave Rats
# 游戏描述：
# 两人对战，每人以8张相同手牌进行游戏，
# 每张手牌以0-7编号，每轮两人同时打出一张牌，
# 点数大者赢得该轮并获得一分
# 首先获得4分，或者双方手牌耗尽时分数高者胜。
# 另外，每张手牌具有一个技能，会影响胜负。

# 导入依存库 ################################################
Loader = require('scgf')
Entity = Loader.Entity
Model = Loader.Model
GameEvent = Model.GameEvent
Listener = Model.Listener
_ = require('lodash')

# 游戏实体结构 ##############################################

class BraveRatsPlayer extends Entity.Player
    init:->
        super()
        @hand 		= @.spawnChild Entity.CardSlot, 'hand'
        @current    = @.spawnChild Entity.CardSlot, 'current'
        @prev       = @.spawnChild Entity.CardSlot, 'prev'
        @discard    = @.spawnChild Entity.CardSlot, 'discard'
        @wins       = @.spawnChild Entity.Counter, 'wins'
        @wins.current = 0

        @hand.spawnChild Prince
        @hand.spawnChild General
        @hand.spawnChild Wizard
        @hand.spawnChild Ambassador
        @hand.spawnChild Assassin
        @hand.spawnChild Spy
        @hand.spawnChild Princess
        @hand.spawnChild Musician

        @.setComponent new Loader.Component.Viewable (viewpoint)=>
                asked : if viewpoint == @ then @getAsked() else undefined
                place : if viewpoint == @ then 'bottom.player' else 'top.player'
                template : 'player'
                name : '@' + @name
                score : @wins.current
                hand : @hand.deck.length


class BraveRatsCard extends Entity.Card
    stat:(@name,@level)->
    addEffect:->
    init:->
        super()
        @.setComponent new Loader.Component.Viewable (viewpoint)=>
            side = viewpoint == @.parent().parent()
            column = @.parent().name
            row = switch 
                when side and column != 'hand' then 'back'
                when not side and column != 'hand' then 'front'
                when side and column == 'hand' then 'bottom'
                when not side and column == 'hand' then 'top'
            return{
                place : row + '.' + column
                template : 'card'
                name : '@card>name>' + @name
                hint : '@card>desc>' + @name
                level : @level
            }
        @addEffect()
    @type_property 'level'

# 游戏事件 ################################################

askEvent = new GameEvent 'event.ask', ->
    player = @player
    player.asked
        play : (choice)=>
            if not choice
                console.log 'empty choice.'
                return false
            if choice.length != 1
                console.log 'choice length ' + choice.length
                return false
            if player.hand != choice[0].parent()
                console.log 'choice parent ' + choice[0].parent().selector()
                console.log 'me is ' + player.selector()
                console.log 'hand is ' + player.hand.selector()
                return false
            return true
askEvent.do = (@player)->@post(@player)


playEvent = new GameEvent 'event.play', ->
    prev = @player.prev.card
    if prev
        prev.moveTo @player.select '.discard'
        prev.notify()
    current = @player.current.card
    if current
        current.moveTo @player.prev
        current.notify()
    play = @player.targets.play[0]
    if play
        play.log 'played.teal', 
            player : '@' + @player.name,
            card : '@card>name>' + play.name
        play.moveTo @player.current
        play.notify()
playEvent.do = (@player)->@post(@player)

winEvent = new GameEvent 'event.win', ->
    if @redlevel > @bluelevel then @round = @red
winEvent.do = (@red,@blue,@redlevel,@bluelevel)->
    @round = @game = false
    @post(@red)

levelEvent = new GameEvent 'event.level', ->
    @level = @player.current.card.level
levelEvent.do = (@player)->
    @post(@player)
    return @level

countWinEvent = new GameEvent 'event.countWin', ->
    @player.wins.current += 1
countWinEvent.do = (@player)->@post(@player)

beforePlay = new GameEvent 'event.beforePlay',->
beforePlay.do = (@player)->
    @prevented = false
    @post(@player)
    return @prevented

# 游戏牌表 ################################################

class Prince extends BraveRatsCard
    addEffect:->
        @stat 'Prince', 7
        @Listeners.add 'win', new Listener 'event.win', (e)->
            @log 'prince.orange',
                card : '@card>name>' + @name
            e.cancelled = true
            e.round = true
        .only (e)-> 
            return false if e.blue.current.card instanceof Wizard
            return false if e.blue.current.card instanceof Prince
            return e.red.current.card == @

class General extends BraveRatsCard
    addEffect:->
        @stat 'General', 6
        @Listeners.add 'level', new Listener 'event.level', (e)->
            if e.conducted
                @log 'general.orange',
                    card : '@card>name>' + e.player.current.card.name
                e.level += 2
        .only (e)-> e.player.prev.card == @

class Wizard extends BraveRatsCard
    addEffect:->
        @stat 'Wizard', 5   

class Ambassador extends BraveRatsCard
    addEffect:->
        @stat 'Ambassador', 4
        @Listeners.add 'countWin', new Listener 'event.countWin', (e)->
            if e.conducted
                @log 'ambassador.orange',
                    player : '@' + e.player.name
                e.player.wins.current += 1
        .only (e)-> 
            mine = e.player.current.card
            theirs = e.player.sibling().current.card
            return false if theirs instanceof Wizard
            return mine == @

class Assassin extends BraveRatsCard
    addEffect:->
        @stat 'Assassin', 3
        @Listeners.add 'win', new Listener 'event.win', (e)->
            if e.conducted
                if e.red.current.card == @
                    @log 'assassin.orange',{}
                e.round = e.redlevel < e.bluelevel
        .only (e)->
            mine = e.red.current.card
            theirs = e.blue.current.card
            return false if mine instanceof Wizard or theirs instanceof Wizard
            return false if mine instanceof Prince or theirs instanceof Prince
            return true if (mine == @) or (theirs == @)
            
class Spy extends BraveRatsCard
    addEffect:->
        @stat 'Spy', 2
        @Listeners.add 'beforePlay', new Listener 'event.beforePlay', (e)->
            if e.conducted 
                @log 'spy.orange', 
                    player : '@' + e.player.name
                askEvent.do e.player
                e.player.collect e.player
                playEvent.do e.player
                e.prevented = true
        .only (e)-> 
            return false if e.player.current.card instanceof Spy
            return e.player.sibling().current.card == @            

class Princess extends BraveRatsCard
    addEffect:->
        @stat 'Princess', 1
        @Listeners.add 'win', new Listener 'event.win', (e)->
            if e.blue.current.card instanceof Prince
                @log 'princess.orange', {}
                e.cancelled = true
                e.game = true
        .only (e)-> e.red.current.card == @

class Musician extends BraveRatsCard
    addEffect:->
        @stat 'Musician', 0
        @Listeners.add 'countWin', new Listener 'event.countWin', (e)->
            e.cancelled = true
            @log 'musician.orange', {}
        .only (e)-> 
            mine = e.player.current.card
            theirs = e.player.sibling().current.card
            return false if mine instanceof Wizard or theirs instanceof Wizard
            return true if (mine == @) or (theirs == @)
            

# 模组接口 ################################################

@config = ->

@avatars = (options)->
    'red' : '.red',
    'blue' : '.blue'

@layout = (options)->[
    ['player', 'hand']
    ['current', 'prev', 'discard']
    ['current', 'prev', 'discard']
    ['player', 'hand']
]

@setup = (game, options)->
    Loader.spawnLayout game,
        players :
            red : BraveRatsPlayer
            blue : BraveRatsPlayer

@run = (game)->
    red = game.root.select '.red'
    blue = game.root.select '.blue'

    while true
        red.log()
        red.log 'score.blue', 
            1 : red.wins.current,
            2 : blue.wins.current

        synced_play = []
        synced_play.push red if not beforePlay.do red
        synced_play.push blue if not beforePlay.do blue

        askEvent.do each for each in synced_play

        red.collectAll(synced_play)

        playEvent.do each for each in synced_play

        red.notify()
        blue.notify()

        round_winner = undefined
        game_winner = undefined

        redlevel = levelEvent.do red
        bluelevel = levelEvent.do blue

        winEvent.do red, blue, redlevel, bluelevel
        round_winner = red if winEvent.round
        game_winner = red if winEvent.game

        winEvent.do blue, red, bluelevel, redlevel
        round_winner = blue if winEvent.round
        game_winner = blue if winEvent.game

        if round_winner
            red.log 'win_round.purple',
                player : '@' + round_winner.name
            countWinEvent.do round_winner
            if round_winner.wins.current >= 4
                game_winner = game_winner or round_winner

        if red.hand.deck.length ==0
            diff = red.wins.current - blue.wins.current
            if diff == 0
                red.log 'tie_game.green', {}
                return
            else if diff > 0
                game_winner = game_winner or red
            else 
                game_winner = game_winner or blue
                
        red.notify()
        blue.notify()

        if game_winner
            red.log 'win_game.green',
                player : '@' + game_winner.name
            scores = {}
            scores[game_winner.name] = 1
            game.logger().score scores
            return
