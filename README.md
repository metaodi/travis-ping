# travis-ping

You can trigger a build manually as described in the [Travis CI documentation](http://about.travis-ci.org/docs/user/how-to-setup-and-trigger-the-hook-manually/).

If you want to trigger a build programmatically, use `travis-ping` to forge a post-receive hook and trigger a build:

    git clone 
    bundle
    require 'travis-ping'
    Travis::Ping.ping 'github-user', 'travis-token', 'repository-owner-name', 'repository-name'
