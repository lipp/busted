require'pl' -- for pretty.write table formating
assert = require'luassert'
spy = require('luassert.spy')
mock = require('luassert.mock')
stub = require('luassert.stub')

busted = {}
busted._COPYRIGHT   = "Copyright (c) 2012 Olivine Labs, LLC."
busted._DESCRIPTION = "A unit testing framework with a focus on being easy to use."
busted._VERSION     = "Busted 1.4"

-- Load default language pack
require('busted.languages.en')

local push = table.insert
local tests = {}
local done = {}
local started = {}
local test_index = 1
local options

step = function(...)
   local steps = {...}
   if #steps == 1 and type(steps[1]) == 'table' then
      steps = steps[1]
   end
   local i = 0
   local next
   next = function()
      i = i + 1
      local step = steps[i]
      if step then
         step(next)
      end
   end
   next()
end

busted.step = step

guard = function(f,test)
   local test = tests[test_index]
   local safef = function(...)
      local result = {pcall(f,...)}
      if result[1] then
         return unpack(result,2)
      else
         local err = result[2]
         if type(err) == "table" then
            err = pretty.write(err)
         end
         test.status.type = 'failure'
         test.status.trace = debug.traceback("", 2)
         test.status.err = err
         test.done()
      end
   end
   return safef
end

busted.guard = guard


local next_test
next_test = function()
   if #done == #tests then
      return
   end
   if not started[test_index] then
      started[test_index] = true
      local test = tests[test_index]
      assert(test,test_index..debug.traceback('',1))
      local steps = {}
      local execute_test = function(next)
         local done = function()
	    assert(test_index <= #tests,'test already done'..test_index)
            done[test_index] = true
            if not options.debug and not options.defer_print then
               options.output.currently_executing(test.status, options)
            end
            test.context:decrement_test_count()
            next()
         end
         test.done = done
         local ok,err = pcall(test.f,done)
         if not ok then
            if type(err) == "table" then
               err = pretty.write(err)
            end
            test.status.type = 'failure'
            test.status.trace = debug.traceback("", 2)
            test.status.err = err
            done()
         end
      end

      local check_before = function(context)
         if context.before then
            local execute_before = function(next)
               context.before(
                  function()
                     context.before = nil
                     next()
                  end)
            end
            push(steps,execute_before)
         end
      end

      local parents = test.context.parents

      for p=1,#parents do
         check_before(parents[p])
      end

      check_before(test.context)

      for p=1,#parents do
         if parents[p].before_each then
            push(steps,parents[p].before_each)
         end
      end

      if test.context.before_each then
         push(steps,test.context.before_each)
      end

      push(steps,execute_test)

      if test.context.after_each then
         push(steps,test.context.after_each)
      end

      local post_test = function(next)
         local post_steps = {}
         local check_after = function(context)
            if context.after then
               if context:all_tests_done() then
                  local execute_after = function(next)
                     context.after(
                        function()
                           context.after = nil
                           next()
                        end)
                  end
                  push(post_steps,execute_after)
               end
            end
         end

         check_after(test.context)

         for p=#parents,1,-1 do
            if parents[p].after_each then
               push(post_steps,parents[p].after_each)
            end
         end

         for p=#parents,1,-1 do
            check_after(parents[p])
         end

         local forward = function(next)
            test_index = test_index + 1
            next_test()
            next()
         end
         push(post_steps,forward)
         step(post_steps)
      end
      push(steps,post_test)
      step(steps)
   end
end

local create_context = function(desc)
   local context = {
      desc = desc,
      parents = {},
      test_count = 0,
      increment_test_count = function(self)
         self.test_count = self.test_count + 1
         for _,parent in ipairs(self.parents) do
            parent.test_count = parent.test_count + 1
         end
      end,
      decrement_test_count = function(self)
         self.test_count = self.test_count - 1
         for _,parent in ipairs(self.parents) do
            parent.test_count = parent.test_count - 1
         end
      end,
      all_tests_done = function(self)
         return self.test_count == 0
      end,
      add_parent = function(self,parent)
         push(self.parents,parent)
      end
   }
   return context
end

local suite_name
local current_context
busted.describe = function(desc,more)
   if not suite_name then
      suite_name = desc
   end
   local context = create_context(desc)
   for i,parent in ipairs(current_context.parents) do
      context:add_parent(parent)
   end
   context:add_parent(current_context)
   local old_context = current_context
   current_context = context
   more()
   current_context = old_context
end

busted.before = function(sync_before,async_before)
   if async_before then
      current_context.before = async_before
   else
      current_context.before = function(done)
         sync_before()
         done()
      end
   end
end

busted.before_each = function(sync_before,async_before)
   if async_before then
      current_context.before_each = async_before
   else
      current_context.before_each = function(done)
         sync_before()
         done()
      end
   end
end

busted.after = function(sync_after,async_after)
   if async_after then
      current_context.after = async_after
   else
      current_context.after = function(done)
         sync_after()
         done()
      end
   end
end

busted.after_each = function(sync_after,async_after)
   if async_after then
      current_context.after_each = async_after
   else
      current_context.after_each = function(done)
         sync_after()
         done()
      end
   end
end

busted.pending = function(name)
   local test = {}
   test.context = current_context
   test.context:increment_test_count()
   test.name = name
   local debug_info = debug.getinfo(2)
   test.f = function(done)
      done()
   end
   test.status = {
      description = name,
      type = 'pending',
      info = {
         source = debug_info.source,
         short_src = debug_info.short_src,
         linedefined = debug_info.linedefined,
      }
   }
   tests[#tests+1] = test
end

busted.it = function(name,sync_test,async_test)
   local test = {}
   test.context = current_context
   test.context:increment_test_count()
   test.name = name

   local debug_info
   if async_test then
      debug_info = debug.getinfo(async_test)
      test.f = async_test
   else
      debug_info = debug.getinfo(sync_test)
      -- make sync test run async
      test.f = function(done)
         sync_test()
         done()
      end
   end
   test.status = {
      description = test.name,
      type = 'success',
      info = {
         source = debug_info.source,
         short_src = debug_info.short_src,
         linedefined = debug_info.linedefined,
      }
   }
   tests[#tests+1] = test
end

busted.reset = function()
   current_context = create_context('Root context')
   tests = {}
   done = {}
   started = {}
   test_index = 1
   suite_name = nil
end

local play_sound = function(failures)
   math.randomseed(os.time())
   
   if options.failure_messages and #options.failure_messages > 0 and
      options.success_messages and #options.success_messages > 0 then
      if failures and failures > 0 then
         io.popen("say \""..options.failure_messages[math.random(1, #options.failure_messages)]:format(failures).."\"")
      else
         io.popen("say \""..options.success_messages[math.random(1, #options.success_messages)].."\"")
      end
   end
end

busted.run = function(opts)
   options = opts
   local ms = os.clock()
   
   suite_name = suite_name or 'Root context'

   if not options.debug and not options.defer_print then      
      print(options.output.header(suit_name,#tests))
   end

   local loop = options.loop or function() end

   repeat
      next_test()
      loop()
   until #done == #tests
   ms = os.clock() - ms

   if not options.debug and options.defer_print then
      print(options.output.header(suit_name,#tests))
   end

   local statuses = {}
   local failures = 0
   for _,test in ipairs(tests) do
      push(statuses,test.status)
      if test.status.type == 'failure' then
         failures = failures + 1
      end
   end
   
   if options.sound then
      play_sound(failures)
   end
   if options.debug then
      return statuses
   else
      if options.defer_print then
         print(options.output.footer(failures))
      end
      return options.output.formatted_status(statuses, options, ms), failures
   end
end

it = busted.it
pending = busted.pending
describe = busted.describe
before = busted.before
after = busted.after
setup = busted.before
teardown = busted.after
before_each = busted.before_each
after_each = busted.after_each
step = step

-- only for internal testing
busted.setup_async_tests = function(yield,loopname)
   describe(
      loopname..' test suite',
      function()
         local before_each_count = 0
         local before_called
         before(
            async,
            function(done)
               yield(guard(
                        function()
                           before_called = true
                           done()
                        end))
                  
            end)

         before_each(
            async,
            function(done)
               yield(guard(
                  function()
                     before_each_count = before_each_count + 1
                     done()
                  end))
            end)

         it(
            'should async succeed',
            async,
            function(done)
               yield(guard(
                  function()
                     assert.is_true(before_called)
                     assert.is.equal(before_each_count,1)
                     done()
                  end))
            end)

         it(
            'should async fail',
            async,
            function(done)
               yield(guard(
                  function()
                     assert.is_truthy(false)
                     done()
                  end))
            end)

         it(
            'should async fails epicly',
            async,
            function(done)
               does_not_exist.foo = 3
            end)

         it(
            'should succeed',
            async,
            function(done)
               done()
            end)

         it(
            'spies should sync succeed',
            function()
               assert.is.equal(before_each_count,5)
               local thing = {
                  greet = function()
                  end
               }
               spy.on(thing, "greet")
               thing.greet("Hi!")
               assert.spy(thing.greet).was.called()
               assert.spy(thing.greet).was.called_with("Hi!")
            end)

         it(
            'spies should async succeed',
            async,
            function(done)
               local thing = {
                  greet = function()
                  end
               }
               spy.on(thing, "greet")
               yield(guard(
                  function()
                     assert.spy(thing.greet).was.called()
                     assert.spy(thing.greet).was.called_with("Hi!")
                     done()
                  end))
               thing.greet("Hi!")
            end)

         describe(
            'with nested contexts',
            function()
               local before_called
               before(
                  async,
                  function(done)
                     yield(guard(
                        function()
                           before_called = true
                           done()
                        end))
                  end)
               it(
                  'nested async test before is called succeeds',
                  async,
                  function(done)
                     yield(guard(
                        function()
                           assert.is_true(before_called)
                           done()
                        end))
                  end)
            end)
         
         pending('is pending')
      end)
end

-- only for internal testing
busted.describe_statuses = function(statuses,print_statuses)
   if print_statuses then
      print('---------- STATUSES ----------')
      print(pretty.write(statuses))
      print('------------------------------')
   end

   describe(
      'Test statuses',
      function()
         it(
            'type is correct',
            function()
               for i,status in ipairs(statuses) do
                  local type = status.type
                  assert.is_truthy(type == 'failure' or type == 'success' or type == 'pending')
                  local succeed = status.description:match('succeed')
                  local fail = status.description:match('fail')
                  local pend = status.description:match('pend')
                  local count = 0
                  if succeed then
                     count = count + 1
                  end
                  if fail then
                     count = count + 1
                  end
                  if pend then
                     count = count + 1
                  end
                  assert.equal(count,1)
                  if succeed then
                     assert(status.type == 'success', status.description)
                  elseif fail then
                     assert(status.type == 'failure', status.description)  
                  elseif pend then
                     assert(status.type == 'pending', status.description)
                  end
               end
            end)

         it(
            'info is correct',
            function()
               for i,status in ipairs(statuses) do
                  assert.is_truthy(status.info.linedefined)
                  assert.is_truthy(status.info.source:match('busted.+init%.lua'))
                  assert.is_truthy(status.info.short_src:match('busted.+init%.lua'))
               end
            end)

         it(
            'provides "err" for failed tests',
            function()
               for i,status in ipairs(statuses) do
                  if status.type == 'failure' then
                     assert.is.equal(type(status.err),'string')
                     assert.is_not.equal(#status.err,0)
                  end
               end
            end)

         it(
            'provides "traceback" for failed tests',
            function()
               for i,status in ipairs(statuses) do
                  if status.type == 'failure' then
                     assert.is.equal(type(status.trace),'string')
                     assert.is_not.equal(#status.trace,0)
                  end
               end
            end)

      end)
end

return busted