# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'Tomcat Install source -defaults', :docker do
  after :all do
    run_shell('pkill -f tomcat', expect_failures: true)
    run_shell('rm -rf /opt/tomcat*', expect_failures: true)
    run_shell('rm -rf /opt/apache-tomcat*', expect_failures: true)
  end

  before :all do
    run_shell("curl --retry 10 --retry-delay 15 -k -o /tmp/sample.war '#{SAMPLE_WAR}'")
  end

  context 'Initial install Tomcat and verification' do
    pp = <<-MANIFEST
      class { 'java':}
      class { 'tomcat':
        catalina_home => '/opt/apache-tomcat9',
      }
      tomcat::install { '/opt/apache-tomcat9':
        source_url     => '#{TOMCAT9_RECENT_SOURCE}',
        allow_insecure => true,
      }
      tomcat::instance { 'tomcat9':
        catalina_base => '/opt/apache-tomcat9/tomcat9',
      }
      tomcat::config::server { 'tomcat9':
        catalina_base => '/opt/apache-tomcat9/tomcat9',
        port          => '8105',
      }
      tomcat::config::server::connector { 'tomcat9-http':
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        port                  => '8180',
        protocol              => 'HTTP/1.1',
        additional_attributes => {
          'redirectPort' => '8543'
        },
      }
      tomcat::config::server::connector { 'tomcat9-ajp':
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        port                  => '8109',
        protocol              => 'AJP/1.3',
        additional_attributes => {
          'redirectPort' => '8543'
        },
      }
      tomcat::war { 'tomcat9-sample.war':
        catalina_base  => '/opt/apache-tomcat9/tomcat9',
        war_source     => '/tmp/sample.war',
        war_name       => 'tomcat9-sample.war',
        allow_insecure => true,
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp)
    end

    it 'is serving a page on port 8180', retry: 5, retry_wait: 10 do
      run_shell('curl --retry 10 --retry-delay 15 localhost:8180') do |r|
        expect(r.stdout).to match(%r{The origin server did not find a current representation for the target resource})
      end
    end

    it 'is serving a JSP page from the war', retry: 5, retry_wait: 10 do
      run_shell('curl --retry 10 --retry-delay 15 localhost:8180/tomcat9-sample/hello.jsp') do |r|
        expect(r.stdout).to match(%r{Sample Application JSP Page})
      end
    end
  end

  context 'Stop tomcat' do
    pp = <<-MANIFEST
      tomcat::service { 'tomcat9':
        catalina_home  => '/opt/apache-tomcat9',
        catalina_base  => '/opt/apache-tomcat9/tomcat9',
        service_ensure => stopped,
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'is not serving a page on port 8180', retry: 5, retry_wait: 10 do
      run_shell('curl localhost:8180', expect_failures: true) do |r|
        expect(r.exit_code).to eq 7
      end
    end
  end

  context 'Start Tomcat' do
    pp = <<-MANIFEST
      tomcat::service { 'tomcat9':
        catalina_home  => '/opt/apache-tomcat9',
        catalina_base  => '/opt/apache-tomcat9/tomcat9',
        service_ensure => running,
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'is serving a page on port 8180', retry: 5, retry_wait: 10 do
      run_shell('curl --retry 10 --retry-delay 15 localhost:8180') do |r|
        expect(r.stdout).to match(%r{The origin server did not find a current representation for the target resource})
      end
    end
  end

  context 'un-deploy the war' do
    pp = <<-MANIFEST
      tomcat::war { 'tomcat9-sample.war':
        war_ensure    => absent,
        catalina_base => '/opt/apache-tomcat9/tomcat9',
        war_source    => '/tmp/sample.war',
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'does not have deployed the war', retry: 5, retry_wait: 10 do
      run_shell('curl --retry 10 --retry-delay 15 localhost:8180/tomcat9-sample/hello.jsp') do |r|
        expect(r.stdout).to match(%r{The origin server did not find a current representation for the target resource})
      end
    end
  end

  context 'remove the connector' do
    pp = <<-MANIFEST
      tomcat::config::server::connector { 'tomcat9-http':
        connector_ensure => 'absent',
        catalina_base    => '/opt/apache-tomcat9/tomcat9',
        port             => '8180',
        notify           => Tomcat::Service['tomcat9'],
      }
      tomcat::service { 'tomcat9':
        catalina_home => '/opt/apache-tomcat9',
        catalina_base => '/opt/apache-tomcat9/tomcat9'
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'is not able to serve pages over port 8180', retry: 5, retry_wait: 10 do
      run_shell('curl localhost:8180', expect_failures: true) do |r|
        expect(r.exit_code).to eq 7
      end
    end
  end

  context 'Service Configuration' do
    pp = <<-MANIFEST
      class{ 'tomcat':}
      tomcat::config::server::service { 'org.apache.catalina.core.StandardService':
        catalina_base     => '/opt/apache-tomcat9/tomcat9',
        class_name        => 'org.apache.catalina.core.StandardService',
        class_name_ensure => 'present',
        service_ensure    => 'present',
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'shoud have a service named FooBar and a class names FooBar' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/server.xml') do |r|
        expect(r.stdout).to match(%r{<Service name="org.apache.catalina.core.StandardService" className="org.apache.catalina.core.StandardService"></Service>})
      end
    end
  end

  context 'add a valve' do
    pp = <<-MANIFEST
      tomcat::config::server::valve { 'logger':
        catalina_base => '/opt/apache-tomcat9/tomcat9',
        class_name    => 'org.apache.catalina.valves.AccessLogValve',
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the conf.xml file' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/server.xml') do |r|
        expect(r.stdout).to match(%r{<Valve className="org.apache.catalina.valves.AccessLogValve"></Valve>})
      end
    end
  end

  context 'remove a valve' do
    pp = <<-MANIFEST
      tomcat::config::server::valve { 'logger':
        catalina_base => '/opt/apache-tomcat9/tomcat9',
        class_name    => 'org.apache.catalina.valves.AccessLogValve',
        valve_ensure  => 'absent',
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the conf.xml file' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/server.xml') do |r|
        expect(r.stdout).not_to match(%r{<Valve className="org.apache.catalina.valves.AccessLogValve"></Valve>})
      end
    end
  end

  context 'add engine and change settings' do
    pp_one = <<-MANIFEST
      tomcat::config::server::engine{'org.apache.catalina.core.StandardEngine':
        default_host               => 'localhost',
        catalina_base              => '/opt/apache-tomcat9/tomcat9',
        background_processor_delay => 5,
        parent_service             => 'org.apache.catalina.core.StandardService',
        start_stop_threads         => 3,
      }
    MANIFEST
    it 'applies the manifest to create the engine without error' do
      apply_manifest(pp_one, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the conf.xml file #5' do
      # validation
      v = '<Service name="org.apache.catalina.core.StandardService" className="org.apache.catalina.core.StandardService"><Engine name="org.apache.catalina.core.StandardEngine" defaultHost="localhost" backgroundProcessorDelay="5" startStopThreads="3"><\/Engine>' # rubocop:disable Layout/LineLength
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/server.xml') do |r|
        expect(r.stdout).to match(%r{#{v}})
      end
    end

    pp_two = <<-MANIFEST
      tomcat::config::server::engine { 'org.apache.catalina.core.StandardEngine':
        default_host               => 'localhost',
        catalina_base              => '/opt/apache-tomcat9/tomcat9',
        background_processor_delay => 999,
        parent_service             => 'org.apache.catalina.core.StandardService',
        start_stop_threads         => 555,
      }
    MANIFEST
    it 'applies the manifest to change the settings without error' do
      apply_manifest(pp_two, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the conf.xml file #999' do
      # validation
      v = '<Service name="org.apache.catalina.core.StandardService" className="org.apache.catalina.core.StandardService"><Engine name="org.apache.catalina.core.StandardEngine" defaultHost="localhost" backgroundProcessorDelay="999" startStopThreads="555"><\/Engine>' # rubocop:disable Layout/LineLength
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/server.xml') do |r|
        expect(r.stdout).to match(%r{#{v}})
      end
    end
  end

  context 'add a host then change settings' do
    pp_one = <<-MANIFEST
      tomcat::config::server::host { 'org.apache.catalina.core.StandardHost':
        app_base              => '/opt/apache-tomcat9/tomcat9/webapps',
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        host_name             => 'hulk-smash',
        additional_attributes => {
          astrological_sign => 'scorpio',
          favorite-beer     => 'PBR',
        },
      }
    MANIFEST
    it 'applies the manifest to create the engine without error' do
      apply_manifest(pp_one, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    # validation
    matches = ['<Host name="hulk-smash".*appBase="/opt/apache-tomcat9/tomcat9/webapps".*></Host>', '<Host name="hulk-smash".*astrological_sign="scorpio".*></Host>', '<Host name="hulk-smash".*favorite-beer="PBR".*></Host>'] # rubocop:disable Layout/LineLength
    it 'has changed the conf.xml file #joined' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/server.xml') do |r|
        matches.each do |m|
          expect(r.stdout).to match(%r{#{m}})
        end
      end
    end

    pp_two = <<-MANIFEST
      tomcat::config::server::host { 'org.apache.catalina.core.StandardHost':
        app_base => '/opt/apache-tomcat9/tomcat9/webapps',
        catalina_base => '/opt/apache-tomcat9/tomcat9',
        host_name => 'hulk-smash',
        additional_attributes => {
          astrological_sign => 'scorpio',
        },
        attributes_to_remove => [
          'favorite-beer',
        ],
      }
    MANIFEST
    it 'applies the manifest to remove a engine attribute without error' do
      apply_manifest(pp_two, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the conf.xml file #seperated' do
      # validation
      v = '<Host name="hulk-smash" appBase="/opt/apache-tomcat9/tomcat9/webapps" astrological_sign="scorpio"><\/Host>'
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/server.xml') do |r|
        expect(r.stdout).to match(%r{#{v}})
      end
    end
  end

  context 'add a context environment' do
    pp = <<-MANIFEST
      tomcat::config::context::environment { 'testEnvVar':
        catalina_base => '/opt/apache-tomcat9/tomcat9',
        type          => 'java.lang.String',
        value         => 'a value with a space',
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the context.xml file' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/context.xml') do |r|
        expect(r.stdout).to match(%r{<Environment name="testEnvVar" type="java.lang.String" value="a value with a space"></Environment>})
      end
    end
  end

  context 'add a context valve' do
    pp = <<-MANIFEST
      tomcat::config::context::valve { 'testValve':
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        class_name            => 'org.apache.catalina.valves.AccessLogValve',
        additional_attributes => {
          prefix  => 'localhost_access_log',
          suffix  => '.txt',
          pattern =>'common'
        },
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the context.xml file' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/context.xml') do |r|
        expect(r.stdout).to match(%r{<Valve className="org.apache.catalina.valves.AccessLogValve".*></Valve>})
      end
    end
  end

  context 'add multiple context valves with the same class_name' do
    pp = <<-MANIFEST
      tomcat::config::context::valve { 'testValve':
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        class_name            => 'org.apache.catalina.valves.AccessLogValve',
        uniqueness_attributes => [
          'prefix',
          'suffix',
        ],
        additional_attributes => {
          prefix  => 'localhost_access_log',
          suffix  => '.txt',
          pattern =>'common'
        },
      }
      tomcat::config::context::valve { 'testValve2':
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        class_name            => 'org.apache.catalina.valves.AccessLogValve',
        uniqueness_attributes => [
          'prefix',
          'suffix',
        ],
        additional_attributes => {
          prefix  => 'localhost_access_log_rare',
          suffix  => '.txt',
          pattern =>'common'
        },
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the context.xml file' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/context.xml') do |r|
        expect(r.stdout).to match(%r{<Valve className="org.apache.catalina.valves.AccessLogValve".*prefix="localhost_access_log".*></Valve>})
        expect(r.stdout).to match(%r{<Valve className="org.apache.catalina.valves.AccessLogValve".*prefix="localhost_access_log_rare".*></Valve>})
      end
    end
  end

  context 'add a context valve with legacy attributes' do
    pp = <<-MANIFEST
      tomcat::config::context::valve { 'testValve':
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        resource_type         => 'org.apache.catalina.valves.AccessLogValve',
        additional_attributes => {
          prefix  => 'localhost_access_log',
          suffix  => '.txt',
          pattern =>'common'
        },
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the context.xml file' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/context.xml') do |r|
        expect(r.stdout).to match(%r{<Valve className="org.apache.catalina.valves.AccessLogValve".*name="testValve".*></Valve>})
      end
    end
  end

  context 'add multiple context valves with legacy attributes' do
    pp = <<-MANIFEST
      tomcat::config::context::valve { 'testValve':
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        resource_type         => 'org.apache.catalina.valves.AccessLogValve',
        additional_attributes => {
          prefix  => 'localhost_access_log',
          suffix  => '.txt',
          pattern =>'common'
        },
      }
      tomcat::config::context::valve { 'testValve2':
        catalina_base         => '/opt/apache-tomcat9/tomcat9',
        resource_type         => 'org.apache.catalina.valves.AccessLogValve',
        additional_attributes => {
          prefix  => 'localhost_access_log_rare',
          suffix  => '.txt',
          pattern =>'common'
        },
      }
    MANIFEST
    it 'applies the manifest without error' do
      apply_manifest(pp, catch_failures: true, acceptable_exit_codes: [0, 2])
    end

    it 'has changed the context.xml file' do
      run_shell('cat /opt/apache-tomcat9/tomcat9/conf/context.xml') do |r|
        expect(r.stdout).to match(%r{<Valve className="org.apache.catalina.valves.AccessLogValve".*name="testValve".*></Valve>})
        expect(r.stdout).to match(%r{<Valve className="org.apache.catalina.valves.AccessLogValve".*name="testValve2".*></Valve>})
      end
    end
  end
end
