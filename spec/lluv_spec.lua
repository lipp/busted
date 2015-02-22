-- Runs internally an lluv async test and checks the returned statuses.

if not pcall(require, "lluv") then
  describe("Testing uv loop", function()
      pending("The 'lluv' loop was not tested because 'lluv' isn't installed")
    end)
else
  local busted = require("busted")
  -- temporarily adjust path to find the test file in the spec directory
  local old_path = package.path
  package.path = "./spec/?.lua"
  local generic_async = require'generic_async_test'
  package.path = old_path
  
  local uv = require 'lluv'
  local loop = uv.default_loop()

  local eps = 1
  local yield = function(done)
    uv.timer(loop):start(eps, function(timer)
      timer:close()                      
      done()
    end)
  end
  
  local statuses = busted.run_internal_test(function()
      
    local create_timer = function(timeout,done)
       uv.timer(loop):start(timeout*1000, function(timer)
         timer:close()
         done()
       end)
    end
    
    setloop('lluv')
      
    generic_async.setup_tests(yield,'lluv',create_timer)
  end)
  
  generic_async.describe_statuses(statuses)
  
  local statuses = busted.run_internal_test(function()
    setloop('lluv')
    it('this should timeout',function(done)
      settimeout(0.01)
      uv.timer(loop):start(100, async(function() done() end))
    end)
      
    it('this should not timeout',function(done)
      settimeout(0.1)
      uv.timer(loop):start(10, async(function() done() end))
    end)
  end)
  
  it('first test is timeout',function()
    local status = statuses[1]
    assert.is_equal(status.type,'failure')
    assert.is_equal(status.err,'test timeout elapsed (0.01s)')
    assert.is_equal(status.trace,'')
  end)
  
  it('second test is not timeout',function()
    local status = statuses[2]
    assert.is_equal(status.type,'success')
  end)

  local f1 = spy.new(function() end)
  local f2 = spy.new(function() end)
  local f3 = spy.new(function() end)
  
  busted.run_internal_test(function()
    setloop('lluv')
    it('setup finally spy for success',function(done)
      finally(f1)
      yield(async(function()
        assert.is_true(true)
        done()
      end))
    end)
      
    it('setup finally spy for error',function(done)
      finally(f2)
      yield(async(function()
        assert.is_true(false)
      end))
    end)
      
    it('setup finally spy for timeout',function(done)
      finally(f3)
      settimeout(0.001)
      lluv.Timer.new(async(function() done() end),0.1):start(loop)
    end)
      
  end)
  
  it('finally spies were all called once', function()
    assert.spy(f1).was_called(1)
    assert.spy(f2).was_called(1)
    assert.spy(f3).was_called(1)
  end)
  
end
  
