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

class BottomSlot extends Entity.CardSlot
    @container @routed.isOwner (->'bottom.'+@name), (->'top.'+@name)

class BackSlot extends Entity.CardSlot
    @container @routed.isOwner (->'front.'+@name), (->'back.'+@name)

class BraveRatsPlayer extends Entity.Player
    @markType
    @children
        hand    : BottomSlot
        current : BackSlot
        prev    : BackSlot
        discard : BackSlot
        wins    : Entity.Counter
    @setup ->
        @wins.current = 0

        @hand.spawnChild Prince
        @hand.spawnChild General
        @hand.spawnChild Wizard
        @hand.spawnChild Ambassador
        @hand.spawnChild Assassin
        @hand.spawnChild Spy
        @hand.spawnChild Princess
        @hand.spawnChild Musician

    @viewer @routed.isSelf ->
        asked : @getAsked()
    @viewer ->
        template : 'player'
        status : @status
        name : '@' + @name
        score : @wins.current
        hand : @hand.deck.length
    @contained @routed.isSelf ->'bottom.player',
    ->'top.player'

class BraveRatsCard extends Entity.Card
    @markType
    @type_property 'level'
    stat:(@name,@level)->

    @viewer ->
        template : 'card'
        name : '@card>name>' + @name
        hint : '@card>desc>' + @name
        level : @level
    
# 游戏事件 ################################################

Events = {}

Events.ask = GameEvent.dispatcher 'event.ask',((@player)->), ->
    player = @player
    player.asked 
        play : (choice)->
            if not choice.length
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

Events.play = GameEvent.dispatcher 'event.play',((@player)->),->
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

Events.win = GameEvent.dispatcher 'event.win',
    (@red,@blue,@redlevel,@bluelevel)->,
    ->if @redlevel > @bluelevel then @round = @red

Events.level = GameEvent.dispatcher 'event.level',((@player)->),->
    @level = @player.current.card.level

Events.score = GameEvent.dispatcher 'event.score',((@player)->),->
    @player.wins.current += 1

Events.prePlay = GameEvent.dispatcher 'event.prePlay',((@player)->),->

# 游戏牌表 ################################################

class Prince extends BraveRatsCard
    @markType
    @setup ->
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
    @markType
    @setup ->
        @stat 'General', 6
        @Listeners.add 'level', new Listener 'event.level', (e)->
            @log 'general.orange',
                card : '@card>name>' + e.player.current.card.name
            e.level += 2
        .only (e)-> e.player.prev.card is @ and e.conducted

class Wizard extends BraveRatsCard
    @markType
    @setup ->
        @stat 'Wizard', 5   

class Ambassador extends BraveRatsCard
    @markType
    @setup ->
        @stat 'Ambassador', 4
        @Listeners.add 'score', new Listener 'event.score', (e)->
            @log 'ambassador.orange',
                player : '@' + e.player.name
            e.player.wins.current += 1
        .only (e)-> 
            mine = e.player.current.card
            theirs = e.player.sibling().current.card
            return false if theirs instanceof Wizard
            return mine == @ and e.conducted

class Assassin extends BraveRatsCard
    @markType
    @setup ->
        @stat 'Assassin', 3
        @Listeners.add 'win', new Listener 'event.win', (e)->
            if e.red.current.card == @
                @log 'assassin.orange',{}
            e.round = e.redlevel < e.bluelevel
        .only (e)->
            mine = e.red.current.card
            theirs = e.blue.current.card
            return false if mine instanceof Wizard or theirs instanceof Wizard
            return false if mine instanceof Prince or theirs instanceof Prince
            return e.conducted if (mine == @) or (theirs == @)
            
class Spy extends BraveRatsCard
    @markType
    @setup ->
        @stat 'Spy', 2
        @Listeners.add 'prePlay', new Listener 'event.prePlay', (e)->
            if e.conducted 
                @log 'spy.orange', 
                    player : '@' + e.player.name
                Events.ask e.player
                e.player.collect e.player
                Events.play e.player
                e.prevented = true
        .only (e)-> 
            return false if e.player.current.card instanceof Spy
            return e.player.sibling().current.card == @            

class Princess extends BraveRatsCard
    @markType
    @setup ->
        @stat 'Princess', 1
        @Listeners.add 'win', new Listener 'event.win', (e)->
            if e.blue.current.card instanceof Prince
                @log 'princess.orange', {}
                e.cancelled = true
                e.game = true
        .only (e)-> e.red.current.card == @

class Musician extends BraveRatsCard
    @markType
    @setup ->
        @stat 'Musician', 0
        @Listeners.add 'score', new Listener 'event.score', (e)->
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
        synced_play.push red if not Events.prePlay(red).prevented
        synced_play.push blue if not Events.prePlay(blue).prevented

        Events.ask each for each in synced_play

        red.collectAll(synced_play)

        Events.play each for each in synced_play

        red.notify()
        blue.notify()

        round_winner = undefined
        game_winner = undefined

        redlevel = Events.level(red).level
        bluelevel = Events.level(blue).level

        winEvent = Events.win red, blue, redlevel, bluelevel
        round_winner = red if winEvent.round
        game_winner = red if winEvent.game

        winEvent = Events.win red, blue, redlevel, bluelevel
        round_winner = blue if winEvent.round
        game_winner = blue if winEvent.game

        if round_winner
            red.log 'win_round.purple',
                player : '@' + round_winner.name
            Events.score round_winner
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
