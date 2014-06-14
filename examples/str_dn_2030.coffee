# Description:
#   client for str_dn_2030/web https://github.com/sorah/str_dn_2030
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_STRDN2030_URL
#   HUBOT_STRDN2030_ZONE
#
# Commands:
#   hubot amp status - show amp status
#   hubot amp volume <volume> - set amp volume
#   hubot amp select <input> - select input
#   hubot amp list inputs - list inputs
#   hubot amp loud - get quiet
#   hubot amp quiet - get louder
#   hubot amp make louder - get louder
#   hubot amp make quiet - get quiet
#   hubot mute amp - mute it
#   hubot unmute amp - unmute it

util = require('util')
module.exports = (robot) ->
  URL = process.env.HUBOT_STRDN2030_URL.replace(/\/$/, '')
  ZONE = process.env.HUBOT_STRDN2030_ZONE or '0'

  request = (msg, path, data) ->
    (callback) ->
      request_url = "#{URL}/zones/#{ZONE}#{path}"
      http = msg.http(request_url)

      #robot.logger.info "amp: #{util.inspect(data)} -> #{request_url}"

      fun = (err, res, body) ->
        if err
          msg.send("Uh, oh: #{err}")
          return
        json = if body && body != ''
          JSON.parse(body) 
        else
          {}
        if json.err
          msg.reply("uh... #{json.err}")
          return
        callback(json)

      if data
        http.header('Content-Type', 'application/json')
            .put(JSON.stringify(data)) fun
      else
        http.get() fun

  robot.respond /amp( status)?$/i, (msg) ->
    request(msg, '') (res)->
      if res.power
        volume = if res.mute
          ", but muted"
        else
          " at volume #{res.volume}"
        msg.send("""
        #{res.active_input.name} is selected#{volume}
        """)
      else
        msg.send("Seems zone #{res.zone} is powered off.")

  robot.respond /(?:amp )?list( all)?( watch| listen)? inputs?/i, (msg) ->
    all = msg.match[1] == ' all'
    watch_or_listen = msg.match[2] && msg.match[2].replace(/^ /, '')
    request(msg, '/inputs') (res)->
      msg.send((for own name, input of res.inputs
        if watch_or_listen == 'watch'
          continue if !all && input.skip.watch
        else if watch_or_listen == 'listen'
          continue if !all && input.skip.listen
        else
          continue if input.skip.watch && input.skip.listen

        "- #{input.name}"
      ).join("\n"))

  robot.respond /amp volume (\d+)/i, (msg) ->
    request(msg, '/volume', {volume: parseInt(msg.match[1], 10)}) (res) ->
      msg.send("Volumed to #{msg.match[1]}.")

  robot.respond /amp mute|mute amp/i, (msg) ->
    request(msg, '/volume', {mute: true}) (res) ->
      msg.send("Muted")

  robot.respond /amp unmute|unmute amp/i, (msg) ->
    request(msg, '/volume', {mute: false}) (res) ->
      msg.send("Resumed.")

  robot.respond /amp(?: too)? loud$|make amp (silent|quiet)|amp--/i, (msg) ->
    request(msg, '/volume') (res) ->
      from = res.volume
      to = res.volume - 2
      request(msg, '/volume', {volume: to}) (res2) ->
        msg.send("Reduced from #{from} to #{to}")

  robot.respond /amp(?: too)? quiet|make amp louder|amp\+\+/i, (msg) ->
    request(msg, '/volume') (res) ->
      from = res.volume
      to = res.volume + 2
      request(msg, '/volume', {volume: to}) (res2) ->
        msg.send("Increased from #{from} to #{to}")

  robot.respond /amp select (.+)/i, (msg) ->
    request(msg, '/active', {input: msg.match[1]}) (res) ->
      msg.send("Tuned to #{res.input.name}.")


