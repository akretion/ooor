require 'active_support/concern'

module Ooor
  module Report
    extend ActiveSupport::Concern

    module ClassMethods
      #Added methods to obtain report data for a model
      def report(report_name, ids, report_type='pdf', context={}) #TODO move to ReportService
        database, user_id, password, context = credentials_from_args(context)
        params = {model: @openerp_model, id: ids[0], report_type: report_type}
        connection.report.report(database, user_id, password, report_name, ids, params)
      end

      def report_get(report_id, context={})
        database, user_id, password, context = credentials_from_args(context)
        connection.report.report_get(database, user_id, password, report_id)
      end

      def get_report_data(report_name, ids, report_type='pdf', context={})
        report_id = self.report(report_name, ids, report_type, context)
        if report_id
          state = false
          attempt = 0
          while not state
            report = self.report_get(report_id, context)
            state = report["state"]
            attempt = 1
            if not state
              sleep(0.1)
              attempt += 1
            else
              return [report["result"],report["format"]]
            end
            if attempt > 100
              logger.debug "OOOR RPC: 'Printing Aborted!'"
              break
            end
          end
        else
          logger.debug "OOOR RPC: 'report not found'"
        end
        return nil
      end

      def credentials_from_context(*args)
        if args[-1][:context_index]
          i = args[-1][:context_index]
          args.delete_at -1
        else
          i = -1
        end
        c = HashWithIndifferentAccess.new(args[i])
        user_id = c.delete(:ooor_user_id) || @connection.config[:user_id]
        password = c.delete(:ooor_password) || @connection.config[:password]
        database = c.delete(:ooor_database) || @connection.config[:database]
        args[i] = @connection.connection_session.merge(c)
        return database, user_id, password, args
      end

      def credentials_from_args(*args)
        if args[-1].is_a? Hash #context
          database, user_id, password, args = credentials_from_context(*args)
        else
          user_id = @connection.config[:user_id]
          password = @connection.config[:password]
          database = @connection.config[:database]
        end
        if user_id.is_a?(String) && user_id.to_i == 0
          user_id = Ooor.cache.fetch("login-id-#{user_id}") do
            @connection.common.login(database, user_id, password)
          end
        end
        return database, user_id.to_i, password, args
      end

    end
  end
end
