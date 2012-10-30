require 'faraday'
require 'multi_json'

module Travis
  # @todo choose a better name?
  module Ping
    # Gets and parses JSON.
    #
    # @param [String] url a URL that returns JSON
    # @return the parsed JSON
    def self.http_get(url)
      MultiJson.load(Faraday.get(url).body)
    end

    # All the documentation about what a payload looks like is inaccurate. Add a
    # custom webhook to find out what it looks like. You can create a webhook
    # URL at http://requestb.in/.
    #
    # @param [String] owner_name a GitHub repository owner
    # @param [String] name a GitHub repository name
    # @return [Hash] a forged post-receive hook payload
    #
    # @note This forgery is probably way more accurate than necessary, but I
    #   can't find the code responsible for reading the payload within Travis.
    #
    # @see How to add a webhook https://help.github.com/articles/post-receive-hooks
    # @see https://github.com/github/github-services/blob/master/lib/service/events/push_helpers.rb
    # @see https://help.github.com/articles/post-receive-hooks
    def self.forge_payload(owner_name, name)
      last_build_id = http_get("https://travis-ci.org/#{owner_name}/#{name}.json")['last_build_id']
      build         = http_get("https://travis-ci.org/builds/#{last_build_id}.json")
      before        = build['compare_url'][/([a-f0-9]+)\.\.\./, 1]

      user       = http_get("https://api.github.com/users/#{owner_name}")
      repository = http_get("https://api.github.com/repos/#{owner_name}/#{name}")
      commit     = http_get("https://api.github.com/repos/#{owner_name}/#{name}/git/commits/#{build['commit']}")
      pusher     = commit['committer'].dup

      repository['owner'] = {
        'type'  => user['type'],
        'login' => user['login'],
        'email' => user['email']
      }

      head_commit = {
        'sha'       => commit['id'],
        'message'   => commit['message'],
        'date'      => commit['authored_date'],
        'commiter'  => { 'name' => commit['committer']['name'], 'email' => commit['committer']['email'] },
        'author'    => { 'name' => commit['author']['name'], 'email' => commit['author']['email'] },
        'compare'   => build['compare_url'] 
      }
      
      # see https://github.com/travis-ci/travis-core/blob/master/lib/travis/services/requests/receive/push.rb
      { 
        'after'       => build['commit'],
        'before'      => before,
        'commits'     => [head_commit],
        'compare'     => build['compare_url'],
        'created'     => false,
        'deleted'     => false,
        'forced'      => false,
        'pusher'      => pusher,
        'ref'         => 'refs/heads/master',
        'repository'  => {
          'name'        => repository['name'],
          'description' => repository['description'],
          '_links'      => { 'html' => { 'href' => repository['url'] } },
          'owner'       => repository['owner']
        }
      }
    end

    # @param [String] user a GitHub username
    # @param [String] token a Travis CI token
    # @param [String] owner_name a GitHub repository owner
    # @param [String] name a GitHub repository name
    #
    # @see Service#http in https://github.com/github/github-services/blob/master/lib/service.rb
    # @see Services::Travis#receive_event https://github.com/github/github-services/blob/master/services/travis.rb
    def self.ping(user, token, owner_name, name)
      http = Faraday.new
      http.request :url_encoded
      http.adapter :net_http
      http.ssl[:verify] = false
      http.basic_auth user, token
      http.post 'http://notify.travis-ci.org', {:payload => MultiJson.dump(forge_payload(owner_name, name))}, 'X-GitHub-Event' => 'push'
    end
  end
end
