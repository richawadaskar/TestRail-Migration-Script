require_relative "transformation"
class Page
  def create_section(title, ancestor, description = "", space_key)
    @title = title
    @ancestor = ancestor
    @description = "#{description}<br/><ac:structured-macro ac:name=\"pagetree\"><ac:parameter ac:name=\"root\"><ac:link><ri:page ri:content-title=\"@self\"/></ac:link></ac:parameter><ac:parameter ac:name=\"searchBox\">true</ac:parameter></ac:structured-macro>"
    @space_key = space_key
    create_page
  end
  def create_case(id, title, version, case_objective = "", preconditions = "", case_steps, missing_links, map_of_id, space_key, username, password, confluence_base_url, testrail_base_url)
    @title = title
    @id = id
    @version = version
    @objective = case_objective
    @preconditions = preconditions
    @case_steps = case_steps
    @space_key = space_key
    obj = Transformation.new
    @description = obj.transform(@id, @title, @objective, @preconditions, @case_steps, missing_links, map_of_id, @space_key, username, password, confluence_base_url, testrail_base_url)
    update_page
  end

  private
  def create_page
    content = {
      "type"=> "page",
      "title"=> @title,
      "space" => {
        "key"=> @space_key
      },
      "ancestors"=> [{
        "id"=> @ancestor
      }],
      "metadata" => {
        "labels" => {
        "results" => [{
            "prefix" => "global",
            "name" => "Unreviewed"
        }]
       }
      },
      "body"=> {
        "storage" => {
          "value"=> @description,
          "representation"=> "storage"
        }
      }
    }
  end

  def update_page
    content = {
      "type"=> "page",
      "id" => @id,
      "title"=> @title,
      "space" => {
        "key"=> @space_key
      },
      "version" => {
          "number" => @version
      },
      "body"=> {
        "storage" => {
          "value"=> @description,
          "representation"=> "storage"
        }
      }
    }
  end
end