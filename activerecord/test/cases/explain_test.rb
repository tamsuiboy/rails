require 'cases/helper'
require 'models/car'
require 'active_support/core_ext/string/strip'

if ActiveRecord::Base.connection.supports_explain?
  class ExplainTest < ActiveRecord::TestCase
    fixtures :cars

    def base
      ActiveRecord::Base
    end

    def connection
      base.connection
    end

    def test_logging_query_plan
      base.logger.expects(:warn).with do |value|
        value.starts_with?('EXPLAIN for:')
      end

      with_threshold(0) do
        Car.where(:name => 'honda').all
      end
    end

    def test_collecting_sqls_for_explain
      base.auto_explain_threshold_in_seconds = nil
      honda = cars(:honda)

      expected_sqls  = []
      expected_binds = []
      callback = lambda do |*args|
        payload = args.last
        unless base.ignore_explain_notification?(payload)
          expected_sqls  << payload[:sql]
          expected_binds << payload[:binds]
        end
      end

      result = sqls = binds = nil
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        with_threshold(0) do
          result, sqls, binds = base.collecting_sqls_for_explain {
            Car.where(:name => 'honda').all
          }
        end
      end

      assert_equal result, [honda]
      assert_equal expected_sqls, sqls
      assert_equal expected_binds, binds
    end

    def test_exec_explain_with_no_binds
      sqls  = %w(foo bar)
      binds = [[], []]

      connection.stubs(:explain).returns('query plan foo', 'query plan bar')
      expected = sqls.map {|sql| "EXPLAIN for: #{sql}\nquery plan #{sql}"}.join("\n")
      assert_equal expected, base.exec_explain(sqls, binds)
    end

    def test_exec_explain_with_binds
      cols = [Object.new, Object.new]
      cols[0].expects(:name).returns('wadus')
      cols[1].expects(:name).returns('chaflan')

      sqls  = %w(foo bar)
      binds = [[[cols[0], 1]], [[cols[1], 2]]]

      connection.stubs(:explain).returns("query plan foo\n", "query plan bar\n")
      expected = <<-SQL.strip_heredoc
        EXPLAIN for: #{sqls[0]} [["wadus", 1]]
        query plan foo

        EXPLAIN for: #{sqls[1]} [["chaflan", 2]]
        query plan bar
      SQL
      assert_equal expected, base.exec_explain(sqls, binds)
    end

    def test_silence_auto_explain
      base.expects(:collecting_sqls_for_explain).never
      base.logger.expects(:warn).never
      base.silence_auto_explain do
        with_threshold(0) { Car.all }
      end
    end

    def with_threshold(threshold)
      current_threshold = base.auto_explain_threshold_in_seconds
      base.auto_explain_threshold_in_seconds = threshold
      yield
    ensure
      base.auto_explain_threshold_in_seconds = current_threshold
    end
  end
end
