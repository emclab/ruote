#--
# Copyright (c) 2005-2010, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++

require 'ruote/util/time'


module Ruote

  #
  # Base methods for storage implementations.
  #
  module StorageBase

    #--
    # configurations
    #++

    def get_configuration (key)

      get('configurations', key)
    end

    #--
    # messages
    #++

    def put_msg (action, options)

      # merge! is way faster than merge (no object creation probably)

      @counter ||= 0

      t = Time.now.utc
      ts = "#{t.strftime('%Y-%m-%d')}!#{t.to_i}.#{'%06d' % t.usec}"
      _id = "#{$$}!#{Thread.current.object_id}!#{ts}!#{'%03d' % @counter}"

      @counter = (@counter + 1) % 1000
        # some platforms (windows) have shallow usecs, so adding that counter...

      msg = options.merge!('type' => 'msgs', '_id' => _id, 'action' => action)

      msg.delete('_rev')
        # in case of message replay

      put(msg)
      #put(msg, :update_rev => true)
      #(@local_msgs ||= []) << options
    end

    #def get_local_msgs
    #  if @local_msgs
    #    r = @local_msgs
    #    @local_msgs = nil
    #    r
    #  else
    #    []
    #  end
    #end

    def get_msgs

      get_many(
        'msgs', nil, :limit => 300
      ).sort { |a, b|
        a['put_at'] <=> b['put_at']
      }
    end

    #--
    # expressions
    #++

    def find_root_expression (wfid)

      get_many('expressions', /!#{wfid}$/).sort { |a, b|
        a['fei']['expid'] <=> b['fei']['expid']
      }.select { |e|
        e['parent_id'].nil?
      }.first
    end

    #--
    # trackers
    #++

    def get_trackers

      get('variables', 'trackers') ||
        { '_id' => 'trackers', 'type' => 'variables', 'trackers' => {} }
    end

    #--
    # ats and crons
    #++

    def get_schedules (delta, now)

      if delta < 1.0

        at = now.strftime('%Y%m%d%H%M%S')
        get_many('schedules', /-#{at}$/)

      elsif delta < 60.0

        at = now.strftime('%Y%m%d%H%M')
        scheds = get_many('schedules', /-#{at}\d\d$/)
        filter_schedules(scheds, now)

      else # load all the schedules

        scheds = get_many('schedules')
        filter_schedules(scheds, now)
      end
    end

    def put_schedule (flavour, owner_fei, s, msg)

      at = if s.is_a?(Time) # at or every
        at
      elsif Ruote.is_cron_string(s) # cron
        Rufus::CronLine.new(s).next_time(Time.now + 1)
      else # at or every
        Ruote.s_to_at(s)
      end
      at = at.utc

      if at <= Time.now.utc && flavour == 'at'
        put_msg(msg.delete('action'), msg)
        return
      end

      sat = at.strftime('%Y%m%d%H%M%S')
      i = "#{flavour}-#{Ruote.to_storage_id(owner_fei)}-#{sat}"

      put(
        '_id' => i,
        'type' => 'schedules',
        'flavour' => flavour,
        'original' => s,
        'at' => Ruote.time_to_utc_s(at),
        'owner' => owner_fei,
        'msg' => msg)

      i
    end

    def delete_schedule (schedule_id)

      s = get('schedules', schedule_id)
      delete(s) if s
    end

    #--
    # engine variables
    #++

    def get_engine_variable (k)

      get_engine_variables['variables'][k]
    end

    def put_engine_variable (k, v)

      vars = get_engine_variables
      vars['variables'][k] = v

      put_engine_variable(k, v) unless put(vars).nil?
    end

    protected

    def get_engine_variables

      get('variables', 'variables') || {
        'type' => 'variables', '_id' => 'variables', 'variables' => {} }
    end

    # Returns all the ats whose due date arrived (now or earlier)
    #
    def filter_schedules (scheds, now)

      now = Ruote.time_to_utc_s(now)

      scheds.select { |sched| sched['at'] <= now }
    end
  end
end

