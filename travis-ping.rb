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
      last_build_id = http_get("http://travis-ci.org/#{owner_name}/#{name}.json")['last_build_id']
      build         = http_get("http://travis-ci.org/builds/#{last_build_id}.json")
      before        = build['compare_url'][/([a-f0-9]+)\.\.\./, 1]

      email      = http_get("http://github.com/api/v2/json/user/show/#{owner_name}")['user']['email']
      repository = http_get("http://github.com/api/v2/json/repos/show/#{owner_name}/#{name}")['repository']
      commit     = http_get("http://github.com/api/v2/json/commits/show/#{owner_name}/#{name}/#{build['commit']}")['commit']
      pusher     = commit['committer'].dup
      pusher.delete 'username'

      repository['owner'] = {
        'name' => repository['owner'],
      }

      head_commit = {
        'added'     => commit['added'],
        'author'    => commit['author'],
        'committer' => commit['committer'],
        # @todo not sure what to do about +distinct+
        'distinct'  => true,
        'id'        => commit['id'],
        'message'   => commit['message'],
        'modified'  => commit['modified'].map{|x| x['filename']},
        'removed'   => commit['modified'],
        'timestamp' => commit['authored_date'],
        'url'       => "https://github.com#{commit['url']}",
      }

      { 'after'       => build['commit'],
        # @todo +before+ will just be six characters long, not 40
        'before'      => before,
        # @todo add other commits
        'commits'     => [head_commit],
        'compare'     => build['compare_url'],
        # @todo these are usually false, but not always
        'created'     => false,
        'deleted'     => false,
        'forced'      => false,
        'head_commit' => head_commit,
        'pusher'      => pusher,
        'ref'         => 'refs/heads/master',
        'repository' => repository,
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
