require 'spec_helper'
require 'thread'
require 'thwait'

describe Innertube::Pool do
  def wait_all(threads)
    message "Waiting on threads: "
    ThreadsWait.all_waits(*threads) do |t|
      message "<#{threads.index(t)}> "
    end
    message "\n"
  end

  let(:pool_members) { pool.instance_variable_get(:@pool) }

  let(:pool) { described_class.new(lambda { [0] }, lambda { |x| }) }

  it 'yields a new object when the pool is empty' do
    pool.take do |x|
      x.should == [0]
    end
  end

  it 'retains a single object for serial access' do
    n = 100
    n.times do |i|
      pool.take do |x|
        x.should == [i]
        x[0] += 1
      end
    end
    pool.size.should == 1
  end

  it 'should be re-entrant' do
    n = 10
    n.times do |i|
      pool.take do |x|
        x.replace [1]
        pool.take do |y|
          y.replace [2]
          pool.take do |z|
            z.replace [3]
            pool.take do |t|
              t.replace [4]
            end
          end
        end
      end
    end
    pool_members.map { |e| e.object.first }.sort.should == [1,2,3,4]
  end


  it 'should unlock when exceptions are raised' do
    begin
      pool.take do |x|
        x << 1
        pool.take do |y|
          x << 2
          y << 3
          raise
        end
      end
    rescue
    end
    pool_members.should be_all {|e| not e.owner }
    pool_members.map { |e| e.object }.should =~ [[0,1,2],[0,3]]
  end

  context 'when BadResource is raised' do
    let(:pool) do
      described_class.new(lambda { mock('resource').tap {|m| m.should_receive(:close) } },
                          lambda { |res| res.close })
    end

    it 'should remove the member from the pool' do
      lambda do
        pool.take do |x|
          raise Innertube::Pool::BadResource
        end
      end.should raise_error(Innertube::Pool::BadResource)
      pool_members.size.should == 0
    end
  end


  context 'threaded access' do
    let!(:pool) { described_class.new(lambda { [] }, lambda { |x| }) }

    it 'should allocate n objects for n concurrent operations' do
      # n threads concurrently allocate and sign objects from the pool
      n = 10
      readyq = Queue.new
      finishq = Queue.new

      threads = (0...n).map do
        Thread.new do
          pool.take do |x|
            readyq << 1
            x << Thread.current
            finishq.pop
          end
        end
      end

      # Give the go-ahead to all threads
      n.times { readyq.pop }

      # Let all threads finish
      n.times { finishq << 1 }

      # Wait for completion
      ThreadsWait.all_waits(*threads)

      # Should have taken exactly n objects to do this
      pool_members.size.should == n

      # And each one should be signed exactly once
      pool_members.map do |e|
        e.object.size.should == 1
        e.object.first
      end.should =~ threads
    end

    it 'take with filter and default' do
      n = 10
      pool = described_class.new(lambda { [] }, lambda { |x| })

      # Allocate several elements of the pool
      q = Queue.new
      finishq = Queue.new
      threads = (0...n).map do |i|
        Thread.new do
          pool.take do |a|
            q << 1
            a << i
            finishq.pop
          end
        end
      end

      # Wait for all threads to have acquired an element
      n.times { q.pop }

      # Let all threads finish
      n.times { finishq << 1 }

      # Wait for completion
      # threads.each {|t| t.join }
      ThreadsWait.all_waits(*threads)

      # Get and delete existing even elements
      got = []
      (n / 2).times do
        begin
          pool.take(
                    :filter => lambda { |x| x.first.even? },
                    :default => [:default]
                    ) do |x|
            got << x.first
            raise Innertube::Pool::BadResource
          end
        rescue Innertube::Pool::BadResource
        end
      end
      got.should =~ (0...n).select(&:even?)

      # This time, no even elements exist, so we should get the default.
      pool.take(:filter => lambda { |x| x.first.even? },
                :default => :default) do |x|
        x.should == :default
      end
    end

    it 'iterates over a snapshot of all connections, even ones in use' do
      started = Queue.new
      n = 30
      threads = (0..n).map do
        Thread.new do
          psleep = 0.75 * rand # up to 50ms sleep
          pool.take do |a|
            started << 1
            a << rand
            sleep psleep
          end
        end
      end

      n.times { started.pop }
      touched = []

      pool.each {|e| touched << e }

      ThreadsWait.all_waits(*threads)

      touched.should be_all {|item| pool_members.any? {|e| e.object == item } }
    end

    context 'clearing the pool' do
      let(:pool) do
        described_class.new(lambda { mock('connection').tap {|m| m.should_receive(:teardown) }},
                            lambda { |b| b.teardown })
      end

      it 'should remove all elements' do
        n = 10
        q, fq = Queue.new, Queue.new

        # Allocate several elements of the pool
        threads = (0...n).map do |i|
          Thread.new do
            pool.take do |a|
              q << i
              sleep(rand * 0.5)
              message "W<#{i}> "
              fq.pop
              message "X<#{i}> "
            end
          end
        end

        # Wait for all threads to have acquired an element
        n.times { message "S<#{q.pop}> " }

        # Start a thread to push stuff onto the finish queue, allowing
        # the worker threads to exit
        pusher = Thread.new do
          n.times do |i|
            message "R<#{i}> "
            fq << 1
            sleep(rand * 0.1)
          end
        end

        # Clear the pool while threads still have elements checked out
        message "S<C> "
        pool.clear
        message "X<C> "

        # Wait for threads to complete
        wait_all(threads + [pusher])
        pool_members.should be_empty
      end
    end

    context 'conditionally deleting members' do
      let(:pool) { described_class.new( lambda { [] }, lambda { |x| } ) }
      it 'should remove them from the pool' do
        n = 10

        # Allocate several elements of the pool
        q = Queue.new
        threads = (0...n).map do |i|
          Thread.new do
            pool.take do |a|
              message "S<#{i}> "
              a << i
              q << i
              Thread.pass
            end
          end
        end

        # Wait for all threads to have acquired an element
        n.times { message "X<#{q.pop}> " }

        # Delete odd elements
        pool.delete_if do |x|
          x.first.odd?
        end

        # Verify odds are gone.
        pool_members.all? do |x|
          x.object.first.even?
        end.should == true

        # Wait for threads
        wait_all threads
      end
    end

    it 'stress test', :timeout => 60 do
      n = 100
      passes = 8
      rounds = 100

      threads = (0...n).map do
        Thread.new do
          rounds.times do |i|
            pool.take do |a|
              a.should == []
              a << Thread.current
              a.should == [Thread.current]

              # Pass and check
              passes.times do
                Thread.pass
                # Nobody else should get ahold of this while I'm idle
                a.should == [Thread.current]
                break if rand > 0.8
              end

              a.delete Thread.current
            end
          end
        end
      end
      wait_all threads
    end
  end
end
