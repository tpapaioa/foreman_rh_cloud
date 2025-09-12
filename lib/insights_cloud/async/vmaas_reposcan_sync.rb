require 'rest-client'

module InsightsCloud
  module Async
    # Triggers VMaaS reposcan sync via IoP gateway when repositories are synced
    class VmaasReposcanSync < ::Actions::EntryAction
      include ::ForemanRhCloud::CertAuth

      # Subscribe to Katello repository sync hook action, if available
      def self.subscribe
        'Actions::Katello::Repository::SyncHook'.constantize
      rescue NameError
        Rails.logger.debug('VMaaS reposcan sync: Repository::SyncHook action not found')
        nil
      end

      def plan(repo, *_args)
        return unless ::ForemanRhCloud.with_iop_smart_proxy?

        repo_id = repo.is_a?(Hash) ? (repo[:id] || repo['id']) : nil
        unless repo_id
          logger.error("VMaaS reposcan sync: missing repository id in SyncHook plan parameters: #{repo.inspect}")
          return
        end

        plan_self
      end

      def run
        url = ::InsightsCloud.vmaas_reposcan_sync_url
        max_attempts = 5
        attempt = 1
        delay = 2

        while attempt <= max_attempts
          begin
            logger.info("VMaaS reposcan sync attempt #{attempt}/#{max_attempts}")

            response = execute_cloud_request(
              method: :put,
              url: url,
              headers: { 'Content-Type' => 'application/json' }
            )

            if response.code >= 200 && response.code < 300
              message = "VMaaS reposcan sync triggered successfully: #{response.code}"
              logger.info(message)
              output[:message] = message
              return response
            elsif response.code == 429
              # Too Many Requests - retry with exponential backoff
              if attempt < max_attempts
                logger.warn("VMaaS reposcan sync failed with 429 (attempt #{attempt}/#{max_attempts}), retrying in #{delay}s...")
                sleep(delay)
                delay *= 2
                attempt += 1
                next
              else
                message = "VMaaS reposcan sync failed after #{max_attempts} attempts with status: #{response.code}, body: #{response.body}"
                logger.error(message)
                output[:message] = message
                return response
              end
            else
              message = "VMaaS reposcan sync failed with status: #{response.code}, body: #{response.body}"
              logger.error(message)
              output[:message] = message
              return response
            end

          rescue RestClient::ExceptionWithResponse => e
            if e.response&.code == 429 && attempt < max_attempts
              logger.warn("VMaaS reposcan sync failed with 429 exception (attempt #{attempt}/#{max_attempts}), retrying in #{delay}s...")
              sleep(delay)
              delay *= 2
              attempt += 1
              next
            else
              message = "VMaaS reposcan sync failed: #{e.response&.code} - #{e.response&.body}"
              logger.error(message)
              output[:message] = message
              raise
            end
          rescue StandardError => e
            message = "Error triggering VMaaS reposcan sync: #{e.message}, response: #{e.respond_to?(:response) ? e.response : nil}"
            logger.error(message)
            output[:message] = message
            raise
          end
        end
      end

      def rescue_strategy_for_self
        Dynflow::Action::Rescue::Skip
      end

      private

      def logger
        action_logger
      end
    end
  end
end
