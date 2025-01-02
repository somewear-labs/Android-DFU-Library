#!/usr/bin/env ruby
require 'optparse'

#
# Publishes a Gradle project hosted on a remote git repo (Github, Bitbucket, etc.) to our private
# Maven repo at https://somewear-artifacts.appspot.com.
#
# ## Usage
# Publish by tag:
# ruby script/github-mvn-publish.rb -u 'https://github.com/minibugdev/DrawableBadge' -t '1.0.3' -m library
#
# Publish by commit:
# ruby script/github-mvn-publish.rb -u 'https://github.com/someweardev/usb-serial-for-android' -c '3febbac689' -m usbSerialForAndroid
#
# ## Setup
# You need to install Maven first:
# brew install maven
#
# You also need to move this file to ~/.m2/settings.xml on your machine:
# https://start.1password.com/open/i?a=I2UOZQZUCNHEXBUFYDFR2YJFVY&v=5ovbsjt5zraua3au2d2h7t57cq&i=prffui6jqvjwoynrcjmy2hfokq&h=somewearlabs.1password.com
#
# If the target library is old, you might need to change your Java version. Use sdkman: https://sdkman.io/
# Examples:
#
# Logback library:
# ruby script/github-mvn-publish.rb -u 'https://github.com/someweardev/logback-android' -m logback-android -t v_3.0.0 -v 3.0.0
# '-t' is the tag of the commit that will be checked out when publishing
# '-v' is what version the artifact will have
# in build.gradle: implementation 'com.github.someweardev:logback-android:3.0.0'
#
# Android DFU library:
# ruby script/github-mvn-publish.rb -u 'https://github.com/someweardev/Android-DFU-Library' -m lib:dfu -t 2.3.0 -v 2.3.0 


def main(options)
  url = options[:url]
  tag = options[:tag]
  branch = options[:branch]
  commit = options[:commit]
  mod = options[:module]
  version_override = options[:version]
  group_override = options[:group]
  artifact_override = options[:artifact]
  gradle_version_override = options[:gradle]

  if url.empty?
    puts 'Error: URL is required.'
    return
  end


  mod_parts = mod.split(':')
  if mod_parts.empty?
    puts 'Error: Module is required, eg; app or lib:dfu'
    return
  end

  url_parts = url.split('/')
  org_id = url_parts[-2].downcase
  group_id = "com.github.#{org_id}"
  repo_name = url_parts.last
  artifact_id = repo_name.downcase
  version = ''
  checkout_prefix = ''
  checkout_param = ''

  if !tag.empty?
    version = tag
    checkout_param = "tags/#{tag}"
  elsif !branch.empty?
    version = branch
    checkout_param = branch
  elsif !commit.empty?
    version = commit
    checkout_param = commit
  else
    puts 'You must specify a tag, branch, or commit.'
    return
  end

  if !version_override.empty?
    version = version_override
  end

  if !artifact_override.empty?
    artifact_id = artifact_override
  end

  if !group_override.empty?
    group_id = group_override
  end

  artifact_path = "#{group_id}:#{artifact_id}:#{version}"
  puts "Publishing \"#{artifact_path}\" to https://somewear-artifacts.appspot.com"

  repo_path = "build/script/#{repo_name}"
  `mkdir -p build/script`
  `rm -rf #{repo_path}`
  `cd build/script && git clone #{url} && git fetch --all --tags`
  `cd #{repo_path} && git checkout #{checkout_param}`
  `mv build/keystore.properties #{repo_path}/keystore.properties`


  if !File.exist?("#{repo_path}/local.properties")
    `echo 'sdk.dir=#{Dir.home}/Library/Android/sdk' > #{repo_path}/local.properties`
  end

  if !gradle_version_override.empty?
    # Gradle wrapper fails to install if the build is failing (which it probably is if theres a gradle version mismatch). To work around this,
    # we install gradle wrapper to a temp directory, then copy the gradle wrapper files to the repo.
    puts "Will install gradle wrapper version #{gradle_version_override}"
    system("mkdir #{repo_path}/gradle-tmp")
    system("cd #{repo_path}/gradle-tmp && touch settings.gradle && gradle wrapper --gradle-version #{gradle_version_override} --distribution-type all")
    system("rm -f #{repo_path}/gradle-tmp/settings.gradle #{repo_path}/gradlew #{repo_path}/gradlew.bat")
    system("cp -r #{repo_path}/gradle-tmp/** #{repo_path}")
    system("touch #{repo_path}/settings.gradle") # Single module project builds won't have a settings.gradle file
  end

  gradle_mod_prefix = mod.empty? ? '' : "#{mod}:"
  gradle_success = system("cd #{repo_path} && ./gradlew #{gradle_mod_prefix}assemble")
  if !gradle_success
    puts 'Gradle build failed. If you are publishing an old library, you might need to change your Java version or Gradle version. To change your java version, ' +
           'use sdkman: https://sdkman.io/. To change your gradle wrapper version, provide the --gradle-version flag (i.e --gradle-version 6.5). See ' +
           'https://developer.android.com/studio/releases/gradle-plugin for finding the correct gradle version that matches with the project\'s Android build tools version.'
    return
  end

  # mvn_mod_prefix = mod_parts.join('/')
  # puts "Maven aar file path=#{mvn_mod_prefix}"
  # mvn_release_prefix = repo
  # aarFilePath = "build/script/#{artifact_id}#{mvn_mod_prefix}/build/outputs/aar/#{mvn_release_prefix}-release.aar"
  # puts "Expecting aar file location to be: #{aarFilePath}"

  mvn_mod_prefix = mod.empty? ? '' : "/#{mod}"
  mvn_release_prefix = mod.empty? ? repo_name : mod
  system("mvn deploy:deploy-file -DgroupId=#{group_id} -DartifactId=#{artifact_id} -Dversion=#{version} -Dpackaging=aar -Dfile=build/script/android-dfu-library/lib/dfu/build/outputs/aar/dfu-release.aar -DrepositoryId=somewear-artifacts -Durl=https://somewear-artifacts.appspot.com")
end

def commands
  # Assign defaults
  options = { url: '', tag: '', branch: '', commit: '', module: '', version: '', gradle: '', group: '', artifact: '' }

  # Parse command line params
  OptionParser.new do |opts|
    opts.banner = "Usage: github-mvn-publish.rb 'https://github.com/your-org/your-library' [options]"
    # opts.on("-m", "--module MODULE_NAME", "Parses and updates the version.txt file in the given module's directory. Defaults to app.") do |m|
    #   options[:module] = m
    # end
    opts.on('-u', '--url URL', 'URL of the github repo to publish.') do |t|
      options[:url] = t
    end
    opts.on('-t', '--tag TAG_NAME', 'Publishes a new version based on the github tag.') do |t|
      options[:tag] = t
    end
    opts.on('-b', '--branch BRANCH_NAME', 'Publishes a new version based on the github branch.') do |t|
      options[:branch] = t
    end
    opts.on('-c', '--commit COMMIT_HASH', 'Publishes a new version based on the github commit short hash.') do |t|
      options[:commit] = t
    end
    opts.on('-v', '--version VERSION', 'Custom artifact version if it is different than the tag, branch, or commit.') do |t|
      options[:version] = t
    end
    opts.on('-m', '--module GRADLE_MODULE', 'Module to publish from in a multi-module project. Format is separated by colon, eg. \'lib:dfu\' or \'app\'') do |t|
      options[:module] = t
    end
    opts.on('--gradle-version GRADLE_VERSION', 'Overrides gradle wrapper version') do |t|
      options[:gradle] = t
    end
    opts.on('-g', '--group GROUP_NAME', 'Overrides the dependency group.') do |t|
      options[:group] = t
    end
    opts.on('-a', '--artifact ARTIFACT_NAME', 'Overrides the dependency artifact name.') do |t|
      options[:artifact] = t
    end
  end.parse!
  options
end

main(commands)
