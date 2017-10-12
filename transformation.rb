require 'redcarpet'
require 'kramdown'
require 'cgi'

class Transformation
  def transform(id, case_title, case_objective, custom_preconditions, case_steps, missing_links, map_of_id, space_key, username, password, confluence_base_url, testrail_base_url)
    @id = id
    @title = case_title
    @objective = ""
    @preconditions = ""
    @body = ""
    @space_key = space_key
    @objective = case_objective if case_objective
    @preconditions = custom_preconditions if custom_preconditions
    @missing_links = missing_links
    @map_of_id = map_of_id
    @username = username
    @password = password
    @confluence_base_url = confluence_base_url
    @testrail_base_url = testrail_base_url
    @body = format_test_steps(case_steps) if case_steps
    format_view
  end

  def format_view

    # add title
    value = "<h2><strong>Test Case Details</strong></h2>"

    #Adding in objective and Test Case Details Table structure
    value += "<div class=\"table-wrap\"><div class=\"table-wrap\"><div class=\"table-wrap\"><div class=\"table-wrap\"><table class=\"relative-table wrapped confluenceTable\" style=\"width: 67.721%;\"><colgroup><col style=\"width: 16.5468%;\"/><col style=\"width: 21.1031%;\"/><col style=\"width: 6.23501%;\"/><col style=\"width: 6.23501%;\"/><col style=\"width: 6.35492%;\"/><col style=\"width: 11.6307%;\"/><col style=\"width: 31.8945%;\"/></colgroup><tbody><tr><th colspan=\"1\" class=\"confluenceTh\"><p>Objective</p></th><td colspan=\"6\" class=\"confluenceTd\">" + format_text(@objective).to_s

    #Adding in preconditions
    value += "</td></tr><tr><th colspan=\"1\" class=\"confluenceTh\">Preconditions</th><td colspan=\"6\" class=\"confluenceTd\">" + format_text(@preconditions).to_s

    #Adding in actual test steps
    value += "</td></tr></tbody></table></div></div></div></div><h2><strong>Test Steps</strong></h2><div class=\"table-wrap\"><div class=\"table-wrap\"><div class=\"table-wrap\"><div class=\"table-wrap\"><table class=\"wrapped confluenceTable\"><colgroup><col/><col/><col/></colgroup><tbody><tr><th style=\"text-align: center;\" class=\"confluenceTh\">Step</th><th style=\"text-align: center;\" class=\"confluenceTh\">Step Description</th><th style=\"text-align: center;\" class=\"confluenceTh\">Expected Result</th></tr>" + @body + "</tbody></table></div></div></div></div><p><br/><br/></p>"

    return value
  end

  private

  def format_test_steps(case_steps)
    steps = ""
    count = 1
    case_steps.each do |step|
      steps += "<tr><td class=\"confluenceTd\">#{count.to_s}</td><td class=\"confluenceTd\">#{format_text(step["content"])}</td><td class=\"confluenceTd\">#{format_text(step["expected"])}</td></tr>"
      count += 1
    end
    return steps
  end

  def format_text(text)

    text.gsub!("<", "&lt;")
    text.gsub!(">", "&gt;")

    text = find_in_text_links(text)
    text = Kramdown::Document.new(text).to_html

    text = find_and_upload_attachments(text)
    text = find_and_upload_cases(text)
    text = find_and_upload_suite_links(text)
    text = fix_code_blocks(text)
    return text
  end

  def find_in_text_links(text)
    links = text.scan(/\[C[\d]+\]/)
    links.each do |case_link|
      case_id = case_link.scan(/[\d]+/)
      mapped = @map_of_id[case_id[0]]
      if mapped
        text.sub!(case_link, "[C#{mapped}](https://#{@confluence_base_url}/wiki/spaces/#{@space_key}/pages/#{mapped})")
      else
        @missing_links[@title] = "case"
      end
    end
    return text
  end

  def fix_code_blocks(text)
    blocks = text.scan(/<code>([\s\S]+?)<\/code>/)
    blocks.each do |block|
      block = block[0]
      fixed_block = block.gsub("&amp;gt;", "&gt;")
      fixed_block = fixed_block.gsub("&amp;lt;", "&lt;")
      text.gsub!(block, fixed_block)
    end
    return text
  end

  def find_and_upload_attachments(text)
    image_list = text.scan(/\<img src=\"index.php\?\/attachments\/get\/[\d]+.+ \/\>/)
    image_list.each do |image|
      begin
        puts "#{@title}: More than 1 attachment in one line!!!" if image.scan(/[\d]+/).length > 1
        image_id = image.match(/[\d]+/).to_s
        Dir.chdir("PATH_TO_ATTACHMENTS_FOLDER")
        filename = Dir.glob("#{image_id}.*").first
        file = File.open("PATH_TO_ATTACHMENTS_FOLDER/#{filename}")
        result = RestClient.post( "https://#{@username}:#{@password}@#{@confluence_base_url}/wiki/rest/api/content/#{@id}/child/attachment",
                                  {'file' => file, multipart: true},
                                  'Accept' => 'application/json',
                                  'X-Atlassian-Token' => 'nocheck'
        )
        parsed = JSON.parse(result.body)
        image_link = CGI::escape_html(parsed["results"][0]["_links"]["download"])
        replace_text = "<span class=\"confluence-embedded-file-wrapper confluence-embedded-manual-size\"><img class=\"confluence-embedded-image\" src=\"https://#{@confluence_base_url}/wiki/download/attachments/#{@id}/#{image_link}\"></img></span>"
        text.sub!(/\<img src=\"index.php\?\/attachments\/get\/[\d]+.+ \/\>/, replace_text)
      rescue RestClient::Exception => ex
        if ex.http_code == 400
          response = RestClient.get("https://#{@username}:#{@password}@#{@confluence_base_url}/wiki/rest/api/content/#{@id}/child/attachment?filename=#{filename}")
          parsed = JSON.parse(response.body)
          image_link = CGI::escape_html(parsed["results"][0]["_links"]["download"])
          replace_text = "<span class=\"confluence-embedded-file-wrapper confluence-embedded-manual-size\"><img class=\"confluence-embedded-image\" src=\"https://#{@confluence_base_url}/wiki/download/attachments/#{@id}/#{image_link}\"></img></span>"
          text.sub!(/\<img src=\"index.php\?\/attachments\/get\/[\d]+.+ \/\>/, replace_text)
          next
        else
          puts @title
          puts "Unexpected Exception occurred,"
        end
      end
    end
    return text
  end

  def find_and_upload_cases(text)
    case_links = text.scan(/\"\/index.php\?\/cases\/view\/[\d]+/)
    case_links += text.scan(/\"https:\/\/#{@testrail_base_url}\/index.php\?\/cases\/view\/[\d]+/)
    case_links += text.scan(/\"index.php\?\/cases\/view\/[\d]+/)
    case_links.each do |d|
      begin
        case_id = d.scan(/[\d]+/)
        mapped = @map_of_id[case_id[0]]
        if mapped
          text.sub!(d, "\"https://#{@confluence_base_url}/wiki/spaces/#{@space_key}/pages/#{mapped}")
        else
          @missing_links[@title] = "case"
        end
      end
    end
    return text
  end

  def find_and_upload_suite_links(text)
    suite_links = text.scan(/\"https:\/\/#{@testrail_base_url}\/index.php\?\/suites\/view\/.+\"/)
    suite_links += text.scan(/\"index.php\?\/suites\/view\/.+\"/)
    suite_links += text.scan(/\"\/index.php\?\/suites\/view\/.+\"/)
    suite_links.each do |d|
      begin
        suite_id = d.scan(/group_id=([\d]+)/)
        mapped = @map_of_id[suite_id[0]]
        if mapped
          text.sub!(d, "\"https://#{@confluence_base_url}/wiki/spaces/#{@space_key}/pages/#{mapped}")
        else
          @missing_links[@title] = "suite"
        end
      end
    end
    return text
  end
end