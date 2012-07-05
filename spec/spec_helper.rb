$: << File.expand_path('../../lib', __FILE__)
$: << File.expand_path('..', __FILE__)
require 'rubygems'
require 'rspec'
require 'innertube'

require 'support/verbose_formatter'
require 'support/timeout'

RSpec.configure do |config|
  config.mock_with :rspec
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true
  if defined?(::Java)
    seed = Time.now.utc
    config.seed = seed
  else
    config.order = :random
  end
end
