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

module.exports = (robot) ->

  robot.hear /\b[A-Z]+\-[0-9]+\b/i, (msg) ->
    msg.send "JIRA: https://jira.workday.com/browse/" + msg.match[0]