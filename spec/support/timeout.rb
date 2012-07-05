require 'timeout'

RSpec.configure do |config|
  config.include Timeout
  config.around(:each) do |example|
    time = example.metadata[:timeout] || 30
    begin
      timeout(time, Timeout::Error) do
        example.run
      end
    rescue Timeout::Error => e
      example.send :set_exception, e
    end
  end
end
