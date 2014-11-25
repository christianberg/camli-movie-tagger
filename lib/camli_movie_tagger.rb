require 'json'
require 'themoviedb'

class CamliMovieTagger
  def initialize(tmdb_api_key)
    Tmdb::Api.key(tmdb_api_key)
  end

  def permanode_attributes_for(sha)
    json = JSON.parse(`camtool describe #{sha}`)
    json['meta'][sha]['permanode']['attr']
  end

  def set_attribute(sha, key, value)
    system('camput', 'attr', sha, key, value, out: '/dev/null')
  end

  def run(arg_string)
    sha = arg_string[0]
    attributes = permanode_attributes_for(sha)
    id = attributes['tmdb_id'][0]
    movie = Tmdb::Movie.detail(id)
    if id == movie.id.to_s
      set_attribute(sha, 'title', movie.title)
    end
  end
end
