require 'spec_helper'
require 'thread'

describe Innertube::Pool do
  let(:pool_members) { subject.instance_variable_get(:@pool) }
  
  describe 'basics' do
    subject do
      described_class.new(lambda { [0] }, lambda { |x| })
    end
    
    it 'yields a new object' do
      subject.take do |x|
        x.should == [0]
      end
    end

    it 'retains a single object for serial access' do
      n = 100
      n.times do |i|
        subject.take do |x|
          x.should == [i]
          x[0] += 1
        end
      end
      subject.size.should == 1
    end

    it 'should be re-entrant' do
      n = 10
      n.times do |i|
        subject.take do |x|
          x.replace [1]
          subject.take do |y|
            y.replace [2]
            subject.take do |z|
              z.replace [3]
              subject.take do |t|
                t.replace [4]
              end
            end
          end
        end
      end
      subject.instance_variable_get(:@pool).map { |e| e.object.first }.sort.should == [1,2,3,4]
    end


    it 'should unlock when exceptions are raised' do
      begin
        subject.take do |x|
          x << 1
          subject.take do |y|
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
      subject do
        described_class.new(lambda do
                              m = mock('resource')
                              m.should_receive(:close)
                              m
                            end,
                            lambda do |res|
                              res.close
                            end)
      end

      it 'should delete' do
        lambda do
          subject.take do |x|
            raise Innertube::Pool::BadResource
          end
        end.should raise_error(Innertube::Pool::BadResource)
        subject.size.should == 0
      end
    end
  end

  describe 'threads' do
    subject {
      described_class.new(lambda { [] }, lambda { |x| })
    }

    it 'should allocate n objects for n concurrent operations' do
      # n threads concurrently allocate and sign objects from the pool
      n = 10
      readyq = Queue.new
      finishq = Queue.new
      threads = (0...n).map do
        Thread.new do
          subject.take do |x|
            readyq << 1
            x << Thread.current
            finishq.pop
          end
        end
      end

      n.times { readyq.pop }
      n.times { finishq << 1 }

      # Wait for completion
      threads.each do |t|
        t.join
      end

      # Should have taken exactly n objects to do this
      subject.size.should == n
      # And each one should be signed exactly once
      pool_members.map do |e|
        e.object.size.should == 1
        e.object.first
      end.should =~ threads
    end

    it 'take with filter and default' do
      n = 10
      subject = described_class.new(lambda { [] }, lambda { |x| })

      # Allocate several elements of the pool
      q = Queue.new
      threads = (0...n).map do |i|
        Thread.new do
          subject.take do |a|
            a << i
            q << 1
            sleep 0.02
          end
        end
      end

      # Wait for all threads to have acquired an element
      n.times { q.pop }

      threads.each do |t|
        t.join
      end

      # Get and delete existing even elements
      got = Set.new
      (n / 2).times do
        begin
          subject.take(
                       :filter => lambda { |x| x.first.even? },
                       :default => [:default]
                       ) do |x|
            got << x.first
            raise Innertube::Pool::BadResource
          end
        rescue Innertube::Pool::BadResource
        end
      end
      got.should == (0...n).select(&:even?).to_set

      # This time, no even elements exist, so we should get the default.
      subject.take(:filter => lambda { |x| x.first.even? },
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
          subject.take do |a|
            started << 1
            a << rand
            sleep psleep
          end
        end
      end

      n.times { started.pop }
      touched = []

      subject.each do |e|
        touched << e
      end

      threads.each do |t|
        t.join
      end

      touched.should be_all {|item| pool_members.find {|e| e.object == item } }
    end

    it 'should clear' do
      n = 10
      subject = described_class.new(
                                    lambda { mock('connection').tap {|m| m.should_receive(:teardown) }},
                                    lambda { |b| b.teardown }
                                    )

      # Allocate several elements of the pool
      q = Queue.new
      threads = (0...n).map do |i|
        Thread.new do
          subject.take do |a|
            q << 1
            sleep 0.1
          end
        end
      end

      # Wait for all threads to have acquired an element
      n.times { q.pop }

      # Clear the pool while threads still have elements checked out
      subject.clear
      pool_members.should be_empty

      # Wait for threads to complete
      threads.each do |t|
        t.join
      end
    end

    it 'should delete_if' do
      n = 10
      subject = described_class.new(
                                    lambda { [] },
                                    lambda { |x| }
                                    )

      # Allocate several elements of the pool
      q = Queue.new
      threads = (0...n).map do |i|
        Thread.new do
          subject.take do |a|
            a << i
            q << 1
            sleep 0.02
          end
        end
      end

      # Wait for all threads to have acquired an element
      n.times { q.pop }

      # Delete odd elements
      subject.delete_if do |x|
        x.first.odd?
      end

      # Verify odds are gone.
      pool_members.all? do |x|
        x.object.first.even?
      end.should == true

      # Wait for threads
      threads.each do |t|
        t.join
      end
    end

    it 'stress test', :slow => true do
      n = 100
      psleep = 0.8
      tsleep = 0.01
      rounds = 100

      threads = (0...n).map do
        Thread.new do
          rounds.times do |i|
            subject.take do |a|
              a.should == []
              a << Thread.current
              a.should == [Thread.current]

              # Sleep and check
              while rand < psleep
                sleep tsleep
                a.should == [Thread.current]
              end

              a.delete Thread.current
            end
          end
        end
      end
      threads.each do |t|
        t.join
      end
    end
  end
end
