# StrDn2030

TODO: Write a gem description

## Installation

``` ruby
gem 'str_dn_2030'
gem 'sinatra' # if you want to use str_dn_2030/web
```

Or install it yourself as:

    $ gem install str_dn_2030

## Usage

### as a Ruby library

#### Connect

``` ruby
require 'str_dn_2030'

remote = StrDn2030::Remote.new('x.x.x.x') # pass your amp's IP address
remote.connect

zone = remote.zones(0) # main zone
```

#### See status

``` ruby
p zone.volume
p zone.powered_on?
p zone.muted?
p zone.headphone?
```

#### Control input

``` ruby
input = zone.active_input
p input.name
p input.preset_name

p zone.inputs #=> Hash

zone.inputs['Chrome'].activate!
zone.active_input = zone.inputs['Apple TV']
```

#### Control volume

``` ruby
zone.volume = 30
zone.mute = true
zone.mute = false
```

### HTTP interface

``` ruby
# config.ru
require 'str_dn_2030'
require 'str_dn_2030/web'

remote = StrDn2030::Remote.new('x.x.x.x')
remote.connect
StrDn2030::Web.set :remote, remote

run StrDn2030::Web
```

```
curl http://localhost:9292/zones/0
```

```
curl http://localhost:9292/zones/0/inputs
```

```
curl http://localhost:9292/zones/0/volume
curl -X PUT \
     -H 'Content-Type: application/json' \
     -d '{"volume": 25}' \
     http://localhost:9292/zones/0/volume
curl -X PUT \
     -H 'Content-Type: application/json' \
     -d '{"mute": true}' \
     http://localhost:9292/zones/0/volume
```

```
curl 'http://localhost:9292/zones/0/inputs/Apple+TV'
curl -X POST 'http://localhost:9292/zones/0/inputs/Apple+TV/activate'
```

```
curl http://localhost:9292/zones/0/active
curl -X PUT \
     -H 'Content-Type: application/json' \
     -d '{"input": "Apple TV"}' \
     http://localhost:9292/zones/0/active
```

## Contributing

1. Fork it ( https://github.com/sorah/str_dn_2030/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
