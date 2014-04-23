# Description:
#   Manage code review reminders
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#   hubot list reviews - List all pending code reviews
#   hubot flush reviews - Flush the code review queue
#   hubot nm - Undo the last addition
#   hubot on it - Mark the last addition as under review
#   (Review|cr|pr) <crucible-url> - Add a code review to the queue
#   <crucible-url> - Add a code review to the queue
#   (<name> is )reviewing <slug> - Remove a code review from the queue
#   ignore <slug> - Remove a code review from the queue
#
# Author:
#   mboynes

class Code_Reviews
  constructor: (@robot) ->
    @room_queues = {}
    @scores = {}
    @current_timeout = null
    @reminder_count = 0

    @robot.brain.on 'loaded', =>
      if @robot.brain.data.code_reviews
        cache = @robot.brain.data.code_reviews
        @room_queues = cache.room_queues || {}
        @scores = cache.scores || {}
        unless Object.keys(@room_queues).length is 0
          @queue()

  update_redis: ->
    @robot.brain.data.code_reviews = { room_queues: @room_queues, scores: @scores }

  find_slug: (room, slug) ->
    console.log "Finding " + slug + " in " + room
    if @room_queues[room]
      for cr, i in @room_queues[room]
        return i if slug == cr.slug
    false

  add: (cr) ->
    return unless cr.user.room
    @room_queues[cr.user.room] ||= []
    @room_queues[cr.user.room].push(cr) if false == @find_slug(cr.user.room, cr.slug)
    @update_redis()
    @reminder_count = 0
    @queue()

  incr_score: (user, dir) ->
    @scores[user] ||= { give: 0, take: 0 }
    @scores[user][dir]++
    @update_redis()

  decr_score: (user, dir) ->
    @scores[user][dir]-- if @scores[user] and @scores[user][dir]
    @update_redis()

  karma: (give, take) ->
    if take == 0 and give > 0
      return 1000000
    return Math.round( ( give / take - 1 ) * 100 ) / 100

  rankings: ->
    gives = takes = karmas = { score: -1, user: 'Nobody' }
    for user, scores of @scores
      if scores.give > gives.score
        gives = { score: scores.give, user: user }
      else if scores.give == gives.score
        gives.user = gives.user + ', ' + user

      if scores.take > takes.score
        takes = { score: scores.take, user: user }
      else if scores.take == takes.score
        takes.user = takes.user + ', ' + user

      karma = @karma(scores.give, scores.take)
      if karma > karmas.score
        karmas = { score: karma, user: user }
      else if karma == karmas.score
        karmas.user = karmas.user + ', ' + user

    [gives, takes, karmas ]

  pop: (user) ->
    return unless user.room
    if @room_queues[user.room] and @room_queues[user.room].length
      cr = @room_queues[user.room].pop()
      delete @room_queues[user.room] if @room_queues[user.room].length is 0
      @check_queue()
    return cr ? cr : false

  remove: (user, slug) ->
    return unless user.room
    i = @find_slug(user.room, slug)
    unless i is false
      cr = @room_queues[user.room].splice(i,1)
      delete @room_queues[user.room] if @room_queues[user.room].length is 0
      @robot.brain.data.code_reviews = @room_queues
      @check_queue()
      return cr.pop()
    false

  check_queue: ->
    if Object.keys(@room_queues).length is 0
      clearTimeout @current_timeout if @current_timeout

  flush: ->
    @room_queues = {}
    @robot.brain.data.code_reviews = @room_queues
    clearTimeout @current_timeout if @current_timeout

  list: (user, verbose) ->
    if user.room and @room_queues[user.room] and @room_queues[user.room].length > 0
      reviews = ''
      for cr in @room_queues[user.room]
        reviews += "\n" + cr.url + '|' + cr.slug
      return "There are pending code reviews. Any takers?" + reviews
    else if true == verbose
      return "There are no pending code reviews for this room."

  queue: (nag_delay = 300000) ->
    clearTimeout @current_timeout if @current_timeout
    if Object.keys(@room_queues).length > 0
      trigger = =>
        for room of @room_queues
          @reminder_count++
          message = @list({room: room})
          @robot.send {room: room}, message
          if @reminder_count is 12
            @robot.send {room: room}, "This queue has been active for an hour, I'll remind hourly from now on."
          else if @reminder_count > 12
            @robot.send {room: room}, "This is an hourly reminder."

        if @reminder_count is 12
          nag_delay = nag_delay * 12
        @queue(nag_delay)
      @current_timeout = setTimeout(trigger, nag_delay)

class Code_Review
  constructor: (@user, @slug, @url) ->


module.exports = (robot) ->

  code_reviews = new Code_Reviews robot

  enqueue_code_review = (msg) =>
    url = msg.match[1]
    slug = msg.match[2]

    findResult = code_reviews.find_slug msg.message.user.room, slug
    console.log findResult
    if findResult
      msg.send slug ' is already in the code review queue'
    else
      cr = new Code_Review msg.message.user, slug, url
      code_reviews.add cr
      code_reviews.incr_score msg.message.user.name, 'take'
      msg.send url + '|' + slug + ' is now in the code review queue. Let me know if anyone starts reviewing this.'

  robot.hear /.*(?:Review|\b[cp]r\b).*(https?:\/\/crucible\.workday\.com\/cru\/([A-Z0-9-]+))/i, enqueue_code_review
  robot.hear /(^https?:\/\/crucible\.workday\.com\/cru\/([A-Z0-9-]+))/i, enqueue_code_review

  robot.hear /(?:([-_a-z0-9]+) is )?(?:reviewing|ignore) ([-_\/A-Z0-9]+).*/i, (msg) ->
    reviewer = msg.match[1] or msg.message.user.name
    slug = msg.match[2]

    if cr = code_reviews.remove msg.message.user, slug
      code_reviews.incr_score reviewer, 'give'
      msg.send "Thanks, #{reviewer}! I removed #{cr.slug} from the code review queue."
    else
      msg.send "Hmm, I could not find #{slug} in the code review queue."

  robot.respond /list reviews/i, (msg) ->
    msg.send code_reviews.list(msg.message.user, true)

  robot.respond /flush reviews/i, (msg) ->
    code_reviews.flush()
    msg.send "The code review queue has been flushed."

  robot.respond /nm|piss off/i, (msg) ->
    cr = code_reviews.pop(msg.message.user)
    if cr and cr.slug
      code_reviews.decr_score cr.user.name, 'take'
      msg.send "Sorry for eavesdropping. I removed #{cr.slug} from the queue."

  robot.respond /(?:([-_a-z0-9]+) is )?on it/i, (msg) ->
    reviewer = msg.match[1] or msg.message.user.name
    cr = code_reviews.pop(msg.message.user)

    if cr and cr.slug
      code_reviews.incr_score reviewer, 'give'
      msg.send "Thanks, #{reviewer}! I removed #{cr.slug} from the code review queue."

  robot.respond /(?:what (?:is|are) the )?(?:code review|cr) (?:rankings|leaderboard)\??/i, (msg) ->
    [gives, takes, karmas] = code_reviews.rankings()
    msg.send "#{gives.user} #{if gives.user.indexOf(',') > -1 then 'have' else 'has'} done the most reviews with #{gives.score}"
    msg.send "#{takes.user} #{if takes.user.indexOf(',') > -1 then 'have' else 'has'} asked for the most code reviews with #{takes.score}"
    msg.send "#{karmas.user} #{if karmas.user.indexOf(',') > -1 then 'have' else 'has'} the best code karma score with #{karmas.score}"

  robot.respond /list all (?:code review|cr) scores/i, (msg) ->
    for user, scores of code_reviews.scores
      msg.send "#{user} has received #{scores.take} reviews and given #{scores.give}. Code karma: #{code_reviews.karma(scores.give, scores.take)}"