# @summary Applies the JVM and JRuby sizing through openvox_tune
#
# openvox_tune edits `JAVA_ARGS` in place, keeping the arguments it does not
# set, and puts `max-active-instances` in a `conf.d` file of its own. Its
# fact reports the server's current settings, so on a host where the server
# is installed in this run it finds nothing yet and the settings apply from
# the next run. Restarting and reloading are this module's job, so
# openvox_tune's own deferred restart is turned off: a change to
# `JAVA_ARGS` restarts the service, a change to the instance count reloads
# it.
#
# @api private
#
class openvox_server::tuning {
  if $openvox_server::state['server_package'] == 'openvox-server' {
    class { 'openvox_tune':
      max_active_instances   => $openvox_server::max_active_instances,
      heap_mb                => $openvox_server::heap_mb,
      reserved_code_cache_mb => $openvox_server::reserved_code_cache_mb,
      restart                => false,
    }

    if $openvox_server::manage_service {
      Augeas <| title == 'openvox_tune JAVA_ARGS' |> ~> Service[$openvox_server::service_name]

      if $openvox_server::service_ensure == 'running' {
        File <| title == '/etc/puppetlabs/puppetserver/conf.d/openvox_tune.conf' |> ~> Exec['openvox_server reload puppetserver']
      }
    }
  } elsif $openvox_server::max_active_instances =~ NotUndef or $openvox_server::heap_mb =~ NotUndef
  or $openvox_server::reserved_code_cache_mb =~ NotUndef {
    notice("openvox_server: ${trusted['certname']} has no openvox-server installed yet; the JVM and JRuby settings apply on the next run.")
  }
}
