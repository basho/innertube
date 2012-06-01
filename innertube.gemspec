$:.push File.expand_path("../lib", __FILE__)
require 'innertube/version'

Gem::Specification.new do |gem|
  gem.name = 'innertube'
  gem.version = Innertube::VERSION
  gem.summary = "A thread-safe resource pool, originally borne in riak-client (Ripple)."
  gem.description = "Because everyone needs their own pool library."
  gem.email = [ "sean@basho.com", "aphyr@aphyr.com" ]
  gem.homepage = "http://github.com/basho/innertube"
  gem.authors = ["Sean Cribbs", "Kyle Kingsbury"]

  gem.add_development_dependency 'rspec', '~> 2.10.0'

  # Files
  ignores = File.read(".gitignore").split(/\r?\n/).reject{ |f| f =~ /^(#.+|\s*)$/ }.map {|f| Dir[f] }.flatten
  gem.files = (Dir['**/*','.gitignore'] - ignores).reject {|f| !File.file?(f) }
  gem.test_files = (Dir['spec/**/*','.gitignore'] - ignores).reject {|f| !File.file?(f) }
  gem.require_paths = ['lib']
end
