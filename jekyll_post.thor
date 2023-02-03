require "thor"
require "stringex"

class JekyllPost < Thor
  desc "new", "create a new post"
  method_option :editor, :default => "subl"
  def new(*title)
    title = title.join(" ")
    date = Time.now.strftime('%Y-%m-%d')
    filename = "_posts/#{date}-#{title.to_url}.markdown"

    if File.exist?(filename)
      abort("#{filename} already exists!")
    end

    puts "Creating new post: #{filename}"
    open(filename, 'w') do |post|
      post.puts "---"
      post.puts "layout: post"
      post.puts "title: \"#{title.gsub(/&/,'&amp;')}\""
      post.puts "date:   #{date} 10:00:00 +0100"
      post.puts "categories: "
      post.puts "author: Matthew Fortunka"
      post.puts "---"
    end

    system(options[:editor], filename)
  end
end