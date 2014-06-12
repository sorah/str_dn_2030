require 'str_dn_2030'
require 'str_dn_2030/web'

remote = StrDn2030::Remote.new(
  ENV['STRDN2030_HOST'],
  ENV['STRDN2030_PORT'] ? ENV['STRDN2030_PORT'].to_i : 33335
)
remote.connect

StrDn2030::Web.set :remote, remote
StrDn2030::Web.set :max_volume, ENV['STRDN2030_MAX_VOLUME'] ? ENV['STRDN2030_MAX_VOLUME'].to_i : 33
run StrDn2030::Web
