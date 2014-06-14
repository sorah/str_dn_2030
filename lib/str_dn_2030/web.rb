require 'str_dn_2030'
require 'sinatra/base'
require 'json'

module StrDn2030
  class Web < Sinatra::Base
    set :max_volume, nil

    helpers do
      def remote
        self.class.remote
      end

      def max_volume
        self.class.max_volume
      end
    end

    get '/' do
      'strdn2030'
    end

    post '/reload' do
      remote.reload
      status 204
    end

    get '/zones/:zone' do
      content_type :json
      zone = remote.zone(params[:zone].to_i)
      {
        zone: params[:zone],
        volume: zone.volume,
        active_input: zone.active_input.as_json,
        mute: zone.muted?,
        power: zone.powered_on?,
        headphone: zone.headphone?,
      }.to_json
    end

    get '/zones/:zone/inputs' do
      content_type :json
      zone = remote.zone(params[:zone].to_i)
      inputs = Hash[zone.inputs.values.uniq.map { |input| [input.name, input.as_json] }]
      {
        inputs: inputs
      }.to_json
    end

    get '/zones/:zone/inputs/:input' do
      content_type :json
      zone = remote.zone(params[:zone].to_i)
      input = zone.inputs[params[:input]]

      unless input
        status 404
        return {error: '404'}.to_json
      end

      input.as_json.to_json
    end

    post '/zones/:zone/inputs/:input/activate' do
      zone = remote.zone(params[:zone].to_i)
      input = zone.inputs[params[:input]]

      unless input
        status 404
        content_type :json
        return {error: '404'}.to_json
      end

      input.activate!

      status 204
      ''
    end

    get '/zones/:zone/active' do
      content_type :json
      zone = remote.zone(params[:zone].to_i)
      zone.active_input.as_json.to_json
    end

    put '/zones/:zone/active' do
      zone = remote.zone(params[:zone].to_i)
      json_params = if request.content_type == 'application/json'
                JSON.parse(request.body.read)
              else
                {}
              end
      input = zone.inputs[json_params['input'] || params[:input]]

      unless input
        status 400
        content_type :json
        return {error: 'no input found'}.to_json
      end

      input.activate!

      status 204
      ''
    end

    get '/zones/:zone/volume' do
      content_type :json
      zone = remote.zone(params[:zone].to_i)

      {
        zone: params[:zone],
        volume: zone.volume,
        mute: zone.muted?,
        headphone: zone.headphone?,
      }.to_json
    end

    put '/zones/:zone/volume' do
      zone = remote.zone(params[:zone].to_i)
      json_params = if request.content_type == 'application/json'
                JSON.parse(request.body.read)
              else
                {}
              end

      volume = json_params['volume'] || params[:volume]
      if volume
        volume = volume.to_i
        if max_volume < volume
          content_type :json
          status 400
          return {error: "over max volume #{max_volume}, given #{volume}"}.to_json
        end

        zone.volume = volume
      end

      mute = json_params.key?('mute') ? json_params['mute'] : params[:mute]
      unless mute.nil?
        p mute
        zone.mute = mute
      end

      status 204
    end
  end
end
