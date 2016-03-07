require File.expand_path("#{File.dirname(__FILE__)}/../test_helper")

class NilClass
  def to_str
    "nil"
  end
end

class MemcachedTest # TODO

  def setup
    @servers = ['localhost:43042', 'localhost:43043', "#{UNIX_SOCKET_NAME}0"]
    @udp_servers = ['localhost:43052', 'localhost:43053']

    # Maximum allowed prefix key size for :hash_with_prefix_key_key => false
    @prefix_key = 'prefix_key_'

    @options = {
      :prefix_key => @prefix_key,
      :hash => :default,
      :distribution => :modula,
      :show_backtraces => true}
    @cache = Memcached.new(@servers, @options)

    @binary_protocol_options = {
      :prefix_key => @prefix_key,
      :hash => :default,
      :distribution => :modula,
      :binary_protocol => true,
      :show_backtraces => true}
    @binary_protocol_cache = Memcached.new(@servers, @binary_protocol_options)

    @udp_options = {
      :prefix_key => @prefix_key,
      :hash => :default,
      :use_udp => true,
      :distribution => :modula,
      :show_backtraces => true}
    @udp_cache = Memcached.new(@udp_servers, @udp_options)

    @noblock_options = {
      :prefix_key => @prefix_key,
      :no_block => true,
      :noreply => true,
      :buffer_requests => true,
      :hash => :default,
      :distribution => :modula,
      :show_backtraces => true}
    @noblock_cache = Memcached.new(@servers, @noblock_options)

    @cas_options = {
      :prefix_key => @prefix_key,
      :hash => :default,
      :distribution => :modula,
      :support_cas => true,
      :show_backtraces => true}
    @cas_cache = Memcached.new(@servers, @cas_options)

    @value = OpenStruct.new(:a => 1, :b => 2, :c => GenericClass)
    @marshalled_value = Marshal.dump(@value)
  end

  # Append and prepend

  def test_append
    @cache.set key, "start", 0, false
    assert_nothing_raised do
      @cache.append key, "end"
    end
    assert_equal "startend", @cache.get(key, false)

    @binary_protocol_cache.set key, "start", 0, false
    assert_nothing_raised do
      @binary_protocol_cache.append key, "end"
    end
    assert_equal "startend", @binary_protocol_cache.get(key, false)
  end

  def test_missing_append
    @cache.delete key rescue nil
    assert_raise(Memcached::NotStored) do
      @cache.append key, "end"
    end
    assert_raise(Memcached::NotFound) do
      assert_equal @value, @cache.get(key)
    end

    @binary_protocol_cache.delete key rescue nil
    assert_raise(Memcached::NotStored) do
      @binary_protocol_cache.append key, "end"
    end
    assert_raise(Memcached::NotFound) do
      assert_equal @value, @binary_protocol_cache.get(key)
    end
  end

  def test_prepend
    @cache.set key, "end", 0, false
    assert_nothing_raised do
      @cache.prepend key, "start"
    end
    assert_equal "startend", @cache.get(key, false)
  end

  def test_missing_prepend
    @cache.delete key rescue nil
    assert_raise(Memcached::NotStored) do
      @cache.prepend key, "end"
    end
    assert_raise(Memcached::NotFound) do
      assert_equal @value, @cache.get(key)
    end
  end

  # CAS

  def test_cas
    value2 = OpenStruct.new(:d => 3, :e => 4, :f => GenericClass)

    # Existing set
    @cas_cache.set key, @value
    @cas_cache.cas(key) do |current|
      assert_equal @value, current
      value2
    end
    assert_equal value2, @cas_cache.get(key)

    # Existing test without marshalling
    @cas_cache.set(key, "foo", 0, false)
    @cas_cache.cas(key, 0, false) do |current|
      "#{current}bar"
    end
    assert_equal "foobar", @cas_cache.get(key, false)

    # Missing set
    @cas_cache.delete key
    assert_raises(Memcached::NotFound) do
      @cas_cache.cas(key) {}
    end

    # Conflicting set
    @cas_cache.set key, @value
    assert_raises(Memcached::ConnectionDataExists) do
      @cas_cache.cas(key) do |current|
        @cas_cache.set key, value2
        current
      end
    end
  end

  def test_multi_cas_with_empty_set
    assert_raises Memcached::NotFound do
      @cas_cache.cas([]) { flunk }
    end
  end

  def test_multi_cas_with_existing_set
    value2 = OpenStruct.new(:d => 3, :e => 4, :f => GenericClass)

    @cas_cache.set key, @value
    result = @cas_cache.cas([key]) do |current|
      assert_equal({key => @value}, current)
      {key => value2}
    end
    assert_equal({key => value2}, result)
    assert_equal value2, @cas_cache.get(key)
  end

  def test_multi_cas_with_different_key
    value2 = OpenStruct.new(:d => 3, :e => 4, :f => GenericClass)
    key2 = "test_multi_cas"

    @cas_cache.delete key2 rescue Memcached::NotFound
    @cas_cache.set key, @value
    result = @cas_cache.cas([key]) do |current|
      assert_equal({key => @value}, current)
      {key2 => value2}
    end
    assert_equal({}, result)
    assert_equal @value, @cas_cache.get(key)
    assert_raises(Memcached::NotFound) do
      @cas_cache.get(key2)
    end
  end

  def test_multi_cas_with_existing_multi_set
    value2 = OpenStruct.new(:d => 3, :e => 4, :f => GenericClass)
    key2 = "test_multi_cas"

    @cas_cache.set key, @value
    @cas_cache.set key2, value2
    result = @cas_cache.cas([key, key2]) do |current|
      assert_equal({key => @value, key2 => value2}, current)
      {key => value2}
    end
    assert_equal({key => value2}, result)
    assert_equal value2, @cas_cache.get(key)
    assert_equal value2, @cas_cache.get(key2)
  end

  def test_multi_cas_with_missing_set
    key2 = "test_multi_cas"

    @cas_cache.delete key rescue Memcached::NotFound
    @cas_cache.delete key2 rescue Memcached::NotFound
    assert_nothing_raised Memcached::NotFound do
      assert_equal({}, @cas_cache.cas([key, key2]) { flunk })
    end
  end

  def test_multi_cas_partial_fulfillment
    value2 = OpenStruct.new(:d => 3, :e => 4, :f => GenericClass)
    key2 = "test_multi_cas"

    @cas_cache.delete key rescue Memcached::NotFound
    @cas_cache.set key2, value2
    result = @cas_cache.cas([key, key2]) do |current|
      assert_equal({key2 => value2}, current)
      {key2 => @value}
    end
    assert_equal({key2 => @value}, result)
    assert_raises Memcached::NotFound do
      @cas_cache.get(key)
    end
    assert_equal @value, @cas_cache.get(key2)
  end

  def test_multi_cas_with_expiration
    value2 = OpenStruct.new(:d => 3, :e => 4, :f => GenericClass)
    key2 = "test_multi_cas"

    @cas_cache.set key, @value
    @cas_cache.set key2, @value, 1
    assert_nothing_raised do
      result = @cas_cache.cas([key, key2]) do |current|
        assert_equal({key => @value, key2 => @value}, current)
        sleep 2
        {key => value2, key2 => value2}
      end
      assert_equal({key => value2}, result)
    end
  end

  def test_multi_cas_with_partial_conflict
    value2 = OpenStruct.new(:d => 3, :e => 4, :f => GenericClass)
    key2 = "test_multi_cas"

    @cas_cache.set key, @value
    @cas_cache.set key2, @value
    assert_nothing_raised Memcached::ConnectionDataExists do
      result = @cas_cache.cas([key, key2]) do |current|
        assert_equal({key => @value, key2 => @value}, current)
        @cas_cache.set key, value2
        {key => @value, key2 => value2}
      end
      assert_equal({key2 => value2}, result)
    end
    assert_equal value2, @cas_cache.get(key)
    assert_equal value2, @cas_cache.get(key2)
  end

  # Error states

  def test_key_with_spaces
    key = "i have a space"
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.set key, @value
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get(key)
    end
  end

  def test_key_with_null
    key = "with\000null"
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.set key, @value
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get(key)
    end

    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      response = @cache.get([key])
    end
  end

  def test_key_with_invalid_control_characters
    key = "ch\303\242teau"
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.set key, @value
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get(key)
    end

    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      response = @cache.get([key])
    end
  end

  def test_key_too_long
    key = "x"*251
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.set key, @value
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get(key)
    end
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @cache.get([key])
    end
  end

  def test_verify_key_disabled
    cache = Memcached.new @servers, :verify_key => false
    key = "i have a space"
    assert_raises(Memcached::ProtocolError) do
      cache.set key, @value
    end
    assert_raises(Memcached::NotFound) do
      cache.get key, @value
    end
  end

  def test_key_error_message
    key = "i have a space"
    @cache.get key, @value
    assert false # Never reached
  rescue Memcached::ABadKeyWasProvidedOrCharactersOutOfRange => e
    assert_match /#{key}/, e.message
  end

  def test_server_error_message
    @cache.set key, "I'm big" * 1000000
    assert false # Never reached
  rescue Memcached::ServerError => e
    assert_match /^"object too large for cache". Key/, e.message
  end

  def test_errno_message
    Rlibmemcached::MemcachedServerSt.any_instance.stubs("cached_errno").returns(1)
    @cache.send(:check_return_code, Rlibmemcached::MEMCACHED_ERRNO, key)
  rescue Memcached::SystemError => e
    assert_match /^Errno 1: "Operation not permitted". Key/, e.message
  end

  # Stats

  def disable_test_stats
    stats = @cache.stats
    assert_equal 3, stats[:pid].size
    assert_instance_of Fixnum, stats[:pid].first
    assert_instance_of String, stats[:version].first

    stats = @binary_protocol_cache.stats
    assert_equal 3, stats[:pid].size
    assert_instance_of Fixnum, stats[:pid].first
    assert_instance_of String, stats[:version].first

    assert_nothing_raised do
      @noblock_cache.stats
    end
    assert_raises(TypeError) do
      @udp_cache.stats
    end
  end

  def test_missing_stats
    cache = Memcached.new('localhost:43041')
    assert_raises(Memcached::SomeErrorsWereReported) { cache.stats }
  end

  # Clone

  def test_clone
    cache = @cache.clone
    assert_equal cache.servers, @cache.servers
    assert_not_equal cache, @cache

    # Definitely check that the structs are unlinked
    assert_not_equal @cache.instance_variable_get('@struct').object_id,
      cache.instance_variable_get('@struct').object_id

    assert_nothing_raised do
      @cache.set key, @value
    end
  end

  # Pipelined, non-blocking IO

  def test_buffered_requests_return_value
    cache = Memcached.new @servers,
      :buffer_requests => true
    assert_nothing_raised do
      cache.set key, @value
    end
    ret = Rlibmemcached.memcached_set(
      cache.instance_variable_get("@struct"),
      key,
      @marshalled_value,
      0,
      Memcached::FLAGS
    )
    assert_equal Rlibmemcached::MEMCACHED_BUFFERED, ret
  end

  def test_no_block_return_value
    assert_nothing_raised do
      @noblock_cache.set key, @value
    end
    ret = Rlibmemcached.memcached_set(
      @noblock_cache.instance_variable_get("@struct"),
      key,
      @marshalled_value,
      0,
      Memcached::FLAGS
    )
    assert_equal Rlibmemcached::MEMCACHED_BUFFERED, ret
  end

  def test_no_block_prepend
    @cache.set key, "help", 0, false
    @noblock_cache.prepend key, "help"
    assert_equal "help",
      @cache.get(key, false)
    @noblock_cache.get "no_exist", false rescue nil
    assert_equal "helphelp",
      @cache.get(key, false)
  end

  def test_no_block_get
    @noblock_cache.set key, @value
    assert_equal @value,
      @noblock_cache.get(key)
  end

  def test_no_block_missing_delete
   @noblock_cache.delete key rescue nil
    assert_nothing_raised do
      @noblock_cache.delete key
      @noblock_cache.delete key
    end
  end

  def test_no_block_set_invalid_key
    assert_raises(Memcached::ABadKeyWasProvidedOrCharactersOutOfRange) do
      @noblock_cache.set "I'm so bad", @value
    end
  end

  def test_no_block_set_object_too_large
    noblock_cache = Memcached.new(@servers, @noblock_options.merge(:noreply => false))
    assert_nothing_raised do
      noblock_cache.set key, "I'm big" * 1000000
    end
    assert_raise( Memcached::ServerIsMarkedDead) do
      @noblock_cache.set key, "I'm big" * 1000000
    end
  end

  def test_no_block_existing_add
    # Should still raise
    noblock_cache = Memcached.new(@servers, @noblock_options.merge(:noreply => false))
    noblock_cache.set key, @value
    assert_raise(Memcached::NotStored) do
      noblock_cache.add key, @value
    end
  end

  # Server removal and consistent hashing

  def test_unresponsive_server
    socket = stub_server 43041

    cache = Memcached.new(
      [@servers.last, 'localhost:43041'],
      :prefix_key => @prefix_key,
      :auto_eject_hosts => true,
      :server_failure_limit => 2,
      :retry_timeout => 1,
      :hash_with_prefix_key => false,
      :hash => :md5,
      :exception_retry_limit => 0
    )

    # Hit second server up to the server_failure_limit
    key2 = 'test_missing_server'
    assert_raise(Memcached::ATimeoutOccurred) { cache.set(key2, @value) }
    assert_raise(Memcached::ATimeoutOccurred) { cache.get(key2, @value) }

    # Hit second server and pass the limit
    key2 = 'test_missing_server'
    begin
      cache.get(key2)
    rescue => e
      assert_equal Memcached::ServerIsMarkedDead, e.class
      assert_match /localhost:43041/, e.message
    end

    # Hit first server on retry
    assert_nothing_raised do
      cache.set(key2, @value)
      assert_equal cache.get(key2), @value
    end

    sleep(2)

    # Hit second server again after restore, expect same failure
    key2 = 'test_missing_server'
    assert_raise(Memcached::ATimeoutOccurred) do
      cache.set(key2, @value)
    end

  ensure
    socket.close
  end

  def test_unresponsive_server_retries_greater_than_server_failure_limit
    socket = stub_server 43041

    cache = Memcached.new(
      [@servers.last, 'localhost:43041'],
      :prefix_key => @prefix_key,
      :auto_eject_hosts => true,
      :server_failure_limit => 2,
      :retry_timeout => 1,
      :hash_with_prefix_key => false,
      :hash => :md5,
      :exception_retry_limit => 3
    )

    key2 = 'test_missing_server'
    assert_nothing_raised do
      cache.set(key2, @value)
      assert_equal cache.get(key2), @value
    end

    assert_nothing_raised do
      cache.set(key2, @value)
      assert_equal cache.get(key2), @value
    end

    sleep(2)

    assert_nothing_raised do
      cache.set(key2, @value)
      assert_equal cache.get(key2), @value
    end
  ensure
    socket.close
  end

  def test_unresponsive_server_retries_equals_server_failure_limit
    socket = stub_server 43041

    cache = Memcached.new(
      [@servers.last, 'localhost:43041'],
      :prefix_key => @prefix_key,
      :auto_eject_hosts => true,
      :server_failure_limit => 2,
      :retry_timeout => 1,
      :hash_with_prefix_key => false,
      :hash => :md5,
      :exception_retry_limit => 3
    )

    key2 = 'test_missing_server'
    begin
      cache.get(key2)
    rescue => e
      assert_equal Memcached::ServerIsMarkedDead, e.class
      assert_match /localhost:43041/, e.message
    end

    assert_nothing_raised do
      cache.set(key2, @value)
      assert_equal cache.get(key2), @value
    end

    sleep(2)

    begin
      cache.get(key2)
    rescue => e
      assert_equal Memcached::ServerIsMarkedDead, e.class
      assert_match /localhost:43041/, e.message
    end

    assert_nothing_raised do
      cache.set(key2, @value)
      assert_equal cache.get(key2), @value
    end
  ensure
    socket.close
  end

  def test_unresponsive_server_retries_less_than_server_failure_limit
    socket = stub_server 43041

    cache = Memcached.new(
      [@servers.last, 'localhost:43041'],
      :prefix_key => @prefix_key,
      :auto_eject_hosts => true,
      :server_failure_limit => 2,
      :retry_timeout => 1,
      :hash_with_prefix_key => false,
      :hash => :md5,
      :exception_retry_limit => 1
    )

    key2 = 'test_missing_server'
    assert_raise(Memcached::ATimeoutOccurred) { cache.set(key2, @value) }
    begin
      cache.get(key2)
    rescue => e
      assert_equal Memcached::ServerIsMarkedDead, e.class
      assert_match /localhost:43041/, e.message
    end

    sleep(2)

    assert_raise(Memcached::ATimeoutOccurred) { cache.set(key2, @value) }
    begin
      cache.get(key2)
    rescue => e
      assert_equal Memcached::ServerIsMarkedDead, e.class
      assert_match /localhost:43041/, e.message
    end
  ensure
    socket.close
  end

  def test_wrong_failure_counter
    cache = Memcached.new(
      [@servers.last],
      :prefix_key => @prefix_key,
      :auto_eject_hosts => true,
      :server_failure_limit => 1,
      :retry_timeout => 1,
      :hash_with_prefix_key => false,
      :hash => :md5,
      :exception_retry_limit => 0
                          )

    # This is an abuse of knowledge, but it's necessary to verify that
    # the library is handling the counter properly.
    struct = cache.instance_variable_get(:@struct)
    server = Memcached::Lib.memcached_server_by_key(struct, "marmotte").first

    # set to ensure connectivity
    cache.set("marmotte", "milk")
    server.server_failure_counter = 0
    cache.quit
    assert_equal 0, server.server_failure_counter
  end

  def test_missing_server
    cache = Memcached.new(
      [@servers.last, 'localhost:43041'],
      :prefix_key => @prefix_key,
      :auto_eject_hosts => true,
      :server_failure_limit => 2,
      :retry_timeout => 1,
      :hash_with_prefix_key => false,
      :hash => :md5,
      :exception_retry_limit => 0
    )

    # Hit second server up to the server_failure_limit
    key2 = 'test_missing_server'
    assert_raise(Memcached::SystemError) { cache.set(key2, @value) }
    assert_raise(Memcached::SystemError) { cache.get(key2, @value) }

    # Hit second server and pass the limit
    key2 = 'test_missing_server'
    begin
      cache.get(key2)
    rescue => e
      assert_equal Memcached::ServerIsMarkedDead, e.class
      assert_match /localhost:43041/, e.message
    end

    # Hit first server on retry
    assert_nothing_raised do
      cache.set(key2, @value)
      assert_equal cache.get(key2), @value
    end

    sleep(2)

    # Hit second server again after restore, expect same failure
    key2 = 'test_missing_server'
    assert_raise(Memcached::SystemError) do
      cache.set(key2, @value)
    end
  end

  def test_unresponsive_with_random_distribution
    socket = stub_server 43041
    failures = [Memcached::ATimeoutOccurred, Memcached::ServerIsMarkedDead]

    cache = Memcached.new(
      [@servers.last, 'localhost:43041'],
      :auto_eject_hosts => true,
      :distribution => :random,
      :server_failure_limit => 1,
      :retry_timeout => 1,
      :exception_retry_limit => 0
    )

    # Provoke the errors in 'failures'
    exceptions = []
    100.times { begin; cache.set key, @value; rescue => e; exceptions << e; end }
    assert_equal failures, exceptions.map { |x| x.class }

    # Hit first server on retry
    assert_nothing_raised { cache.set(key, @value) }

    # Hit second server again after restore, expect same failures
    sleep(2)
    exceptions = []
    100.times { begin; cache.set key, @value; rescue => e; exceptions << e; end }
    assert_equal failures, exceptions.map { |x| x.class }
  ensure
    socket.close
  end

  def test_consistent_hashing
    keys = %w(EN6qtgMW n6Oz2W4I ss4A8Brr QShqFLZt Y3hgP9bs CokDD4OD Nd3iTSE1 24vBV4AU H9XBUQs5 E5j8vUq1 AzSh8fva PYBlK2Pi Ke3TgZ4I AyAIYanO oxj8Xhyd eBFnE6Bt yZyTikWQ pwGoU7Pw 2UNDkKRN qMJzkgo2 keFXbQXq pBl2QnIg ApRl3mWY wmalTJW1 TLueug8M wPQL4Qfg uACwus23 nmOk9R6w lwgZJrzJ v1UJtKdG RK629Cra U2UXFRqr d9OQLNl8 KAm1K3m5 Z13gKZ1v tNVai1nT LhpVXuVx pRib1Itj I1oLUob7 Z1nUsd5Q ZOwHehUa aXpFX29U ZsnqxlGz ivQRjOdb mB3iBEAj)

    # Five servers
    cache = Memcached.new(
      @servers + ['localhost:43044', 'localhost:43045', 'localhost:43046'],
      :prefix_key => @prefix_key
    )

    cache.flush
    keys.each do |key|
      cache.set(key, @value)
    end

    # Pull a server
    cache = Memcached.new(
      @servers + ['localhost:43044', 'localhost:43046'],
      :prefix_key => @prefix_key
    )

    failed = 0
    keys.each_with_index do |key, i|
      begin
        cache.get(key)
      rescue Memcached::NotFound
        failed += 1
      end
    end

    assert(failed < keys.size / 3, "#{failed} failed out of #{keys.size}")
  end

  # Concurrency

  def test_thread_contention
    threads = []
    4.times do |index|
      threads << Thread.new do
        cache = @cache.clone
        assert_nothing_raised do
          cache.set("test_thread_contention_#{index}", index)
        end
        assert_equal index, cache.get("test_thread_contention_#{index}")
      end
    end
    threads.each {|thread| thread.join}
  end

  # Hash

  def test_hash
    assert_equal 3157003241,
      Rlibmemcached.memcached_generate_hash_rvalue("test", Rlibmemcached::MEMCACHED_HASH_FNV1_32)
  end

  def test_noop_hash
    %w[foo bar baz qux quux].each do |word|
      assert_equal 1,
        Rlibmemcached.memcached_generate_hash_rvalue(word, Rlibmemcached::MEMCACHED_HASH_NONE)
    end
  end

  # Memory cleanup

  def test_reset
    original_struct = @cache.instance_variable_get("@struct")
    assert_nothing_raised do
      @cache.reset
    end
    assert_not_equal original_struct,
      @cache.instance_variable_get("@struct")
  end

  # NOTE: This breaks encapsulation, but there's no other easy way to test this without
  # mocking out Rlibmemcached calls
  def test_reraise_invalid_return_code
    assert_raise Memcached::Error do
      @cache.send(:check_return_code, 5000)
    end
  end

  private

  def key
    caller.first[/.*[` ](.*)'/, 1] # '
  end

  def stub_server(port)
    socket = TCPServer.new('127.0.0.1', port)
    Thread.new { socket.accept }
    socket
  end

end
