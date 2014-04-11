# Description:
#   Make workbot interact with jiras
#
# Dependencies:
#   None
#
# Configuration:
#   None
#
# Commands:
#
# Author:
#   john.welsh

Url = require 'url'
NRP = require('node-redis-pubsub')

redisUrl = Url.parse process.env.HUBOT_REDISADAPTER_URL

console.log redisUrl

config = 
  host: redisUrl.hostname
  port: redisUrl.port
  auth: redisUrl.auth.split(":")[1]
  scope: 'hubot-redis-adapter'

nrp = new NRP config

module.exports = (robot) ->
  robot.respond /(\b[A-Z]+\-[0-9]+\b)/i, (msg) ->
    nrp.emit('jiraLookup', {jiraID: msg.match[1]})
    msg.send "JIRA: https://jira.workday.com/browse/" + msg.match[1]