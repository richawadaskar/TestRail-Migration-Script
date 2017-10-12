require_relative "page"
require "json"
require "rest-client"
require "cgi"
require "redcarpet"

map_of_id = {}
missing_links = Hash.new
main_ancestor_id = 86832612
space_key = ENV['SPACE_KEY']
username = ENV['CONFLUENCE_USERNAME']
password = ENV['CONFLUENCE_PASSWORD']
confluence_base_url = ENV['CONFLUENCE_BASE_URL']
testrail_base_url = ENV['TESTRAIL_BASE_URL']

data = JSON.parse(File.read("section_names.json"))

markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)

data.each do |section|
  begin
    id = section["id"]
    title = section["name"]
    ancestor = section["parent_id"]? map_of_id[section["parent_id"].to_s] : main_ancestor_id
    description = markdown.render(CGI::escape_html(section["description"])) if section["description"]
    page = Page.new
    content = page.create_section(title, ancestor, description, space_key)
    response = RestClient.post("https://#{username}:#{password}@#{confluence_base_url}/wiki/rest/api/content/", content.to_json, :content_type => :json, :accept => :json)
    parsed = JSON.parse(response)
    map_of_id[id.to_s] = parsed["id"]
  rescue RestClient::Exception => ex
    if ex.http_code == 400
      title = CGI::escape(title)
      puts "#{title}: #{ex.http_body}"
      response = RestClient.get("https://#{username}:#{password}@#{confluence_base_url}/wiki/rest/api/content?spaceKey=#{space_key}&title=#{title}&expand=space,body.view,version,container")
      parsed = JSON.parse(response.body)
      map_of_id[id.to_s] = parsed["results"][0]["id"]
      next
    end
    puts "#{title}: #{ex.message}"
    next
  end
end

file = File.read("test_cases.json")
data = JSON.parse(file)

data.each do |test_case|
  begin
    id = test_case["id"]
    title = test_case["title"]
    ancestor = test_case["section_id"]? map_of_id[test_case["section_id"].to_s] : main_ancestor_id
    page = Page.new
    content = page.create_section(title, ancestor, "", space_key)
    response = RestClient.post("https://#{username}:#{password}@#{confluence_base_url}/wiki/rest/api/content/", content.to_json, :content_type => :json, :accept => :json)
    parsed = JSON.parse(response)
    map_of_id[id.to_s] = parsed["id"]
  rescue RestClient::Exception => ex
    if ex.http_code == 400
      title = CGI::escape(title)
      response = RestClient.get("https://#{username}:#{password}@#{confluence_base_url}/wiki/rest/api/content?spaceKey=#{space_key}&title=#{title}&expand=space,body.view,version,container")
      parsed = JSON.parse(response.body)
      map_of_id[id.to_s] = parsed["results"][0]["id"]
      next
    end
    puts title
    puts ex.http_body
    next
  end
end

puts map_of_id
puts "Switching to updating"

data.each do |test_case|
  begin
    id = map_of_id[test_case["id"].to_s]
    title = test_case["title"]
    objective = test_case["custom_testcase_objective"]
    preconds = test_case["custom_preconds"]
    case_steps = test_case["custom_steps_separated"]
    response = RestClient.get("https://#{username}:#{password}@#{confluence_base_url}/wiki/rest/api/content?spaceKey=#{space_key}&title=#{CGI::escape(title)}&expand=space,body.view,version,container")
    parsed = JSON.parse(response.body)
    version = parsed["results"][0]["version"]["number"] + 1
    page = Page.new
    content = page.create_case(id, title, version, objective, preconds, case_steps, missing_links, map_of_id, space_key, username, password, confluence_base_url, testrail_base_url)
    response = RestClient.put("https://#{username}:#{password}@#{confluence_base_url}/wiki/rest/api/content/#{id}", content.to_json, :content_type => :json, :accept => :json)
    parsed = JSON.parse(response)
    map_of_id[id.to_s] = parsed["id"]
  rescue RestClient::Exception => ex
    puts "#{title} in rescue"
    puts ex.http_body
    if ex.http_code == 400
      next
    end
  end
end

puts "These are the dead links: #{missing_links}"