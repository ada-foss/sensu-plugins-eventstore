require 'date'

Gem::Specification.new do |s|
  s.name                   = 'sensu-plugins-eventstore'
  s.version                = '0.0.15'
  s.date                   = Date.today.to_s
  s.summary                = "sensu-plugins for event store"
  s.description            = "A collection of checks and metrics for event store, designed for sensu"
  s.authors                = ['Jamie Wroe']
  s.email                  = 'Jamie.Wroe@live.co.uk'
  s.executables            = Dir.glob('bin/**/*').map { |file| File.basename(file) }
  s.files                  = Dir.glob('{bin,lib}/**/*') + %w(LICENSE README.md CHANGELOG.md)
  s.homepage               = 'https://github.com/JWroe/sensu-plugins-eventstore'
  s.license                = 'MIT'
  s.required_ruby_version  = '>= 1.9.3'
  s.metadata               = { 'maintainer'         => '@JWroe',
                               'development_status' => 'active',
                               'production_status'  => 'unstable - testing recommended',
                               'release_draft'      => 'false',
                               'release_prerelease' => 'false'
				             }
  s.platform               = Gem::Platform::RUBY
  s.post_install_message   = 'You can use the embedded Ruby by setting EMBEDDED_RUBY=true in /etc/default/sensu'
  
  s.add_development_dependency 'yard',                      '~> 0.8'
  s.add_development_dependency 'rake',                      '~> 10.0'
  
  s.add_runtime_dependency 'sensu-plugin',     '1.2.0'
  s.add_runtime_dependency 'nokogiri',         '1.6.7.2'
end