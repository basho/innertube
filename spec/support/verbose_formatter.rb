require 'rspec/core/formatters/base_text_formatter'

class VerboseFormatter < RSpec::Core::Formatters::BaseTextFormatter
  attr_reader :column, :current_indentation
  def initialize(*args)
    super
    @mutex = Mutex.new
    @column = @current_indentation = 0
  end

  def start(count)
    super
    output.puts
    output.puts "Running suite with seed #{RSpec.configuration.seed}\n"
    output.puts
  end

  def example_group_started(example_group)
    super
    # $stderr.puts example_group.metadata.inspect
    output.puts "#{padding}#{example_group.metadata[:example_group][:description_args].first}"
    indent!
  end

  def example_group_finished(example_group)
    super
    outdent!
  end

  def example_started(example)
    output.puts "#{padding}#{example.description}:"
    indent!
  end

  def message(m)
    @mutex.synchronize do
      messages = m.split(/\r?\n/).reject {|s| s.empty? }
      messages.each do |message|
        if column + message.length > max_columns
          output.puts
          @column = current_indentation
        end
        if at_left_margin?
          output.print "#{padding}#{message}"
        else
          output.print message
        end
        @column += message.length
      end
    end
  end

  def example_passed(example)
    super
    print_example_result green("PASS")
  end

  def example_failed(example)
    super
    print_example_result red("FAIL")
  end

  def example_pending(example)
    super
    print_example_result yellow("PENDING: #{example.metadata[:execution_result][:pending_message]}")
  end

  private
  def print_example_result(text)
    output.puts unless at_left_margin?
    output.puts "#{padding}#{text}"
    output.puts
    outdent!
  end

  def at_left_margin?
    column == current_indentation
  end

  def max_columns
    @max_columns ||= ENV.include?('COLUMNS') ? ENV['COLUMNS'].to_i : 72
  end

  def indent_width
    2
  end

  def padding
    ' ' * current_indentation
  end

  def indent!
    @current_indentation += indent_width
    @column = @current_indentation
  end

  def outdent!
    @current_indentation -= indent_width
    @column = @current_indentation
  end
end

module ExposeFormatter
  def message(string)
    RSpec.configuration.formatters.first.message(string)
  end
end

RSpec.configure do |config|
  config.include ExposeFormatter
  config.add_formatter VerboseFormatter
end
