require 'sinatra'
require 'sinatra/base'
require 'json'
require 'pp'
require 'dotenv'
require 'htph'
require 'erb'

Dotenv.load

class LoginScreen < Sinatra::Base
  #todo: noncrazy, nonstupid user auth
  enable :sessions
   
  get('/login') { erb :login }

  post('/login') do
    open('.users').each do | line |
      u, pw = line.chomp.split(':')
      if params[:name] == u and params[:password] == pw
        session['user_name'] = params[:name]
        redirect '/compare' 
      end
    end
    #else
    redirect '/login'
  end
end

class MrApp < Sinatra::Base
  set :bind, '0.0.0.0'
  use LoginScreen

  before do
    unless session['user_name']
      redirect '/login'
    end
  end

  @@db = HTPH::Hathidb::Db.new();
  @@conn = @@db.get_conn();

  @@get_rec_sql = "SELECT hf.file_path, hg.record_id FROM hathi_gd hg 
                    LEFT JOIN hathi_input_file hf ON hg.file_id = hf.id
                   WHERE hg.id = ? LIMIT 1"
  @@get_rec = @@conn.prepare(@@get_rec_sql)

  @@get_pair_sql = "SELECT id, first_id, second_id FROM mr_pairs WHERE id = ? LIMIT 1"
  @@get_pair = @@conn.prepare(@@get_pair_sql)

  @@add_review_sql = "INSERT INTO manual_reviews (pair_id, relationship, note, reviewer)
                      VALUES (?, ?, ?, ?)"
  @@add_review = @@conn.prepare(@@add_review_sql)
  
  @@update_pair_sql = "UPDATE mr_pairs SET review_count = review_count + 1 
                      WHERE id = ?"
  @@update_pair = @@conn.prepare(@@update_pair_sql)

  @@get_pairs_sql = "SELECT * FROM mr_pairs WHERE review_count > 0 LIMIT ?, 100"
  @@get_pairs = @@conn.prepare(@@get_pairs_sql)

  get '/' do
    "Manual review of government documents."
  end

  get '/compare' do
    pair = get_next_pair
    redirect to('/compare/'+pair[:id].to_s) 
  end

  get '/compare/:pair_id' do |pair_id|
    recs = {}
    @@get_pair.enumerate(pair_id) do | pair |
      recs = get_recs( pair[:first_id], pair[:second_id] )
    end

    #extract some of main fields
    first = JSON.parse(recs[:first])
    second = JSON.parse(recs[:second])
    begin
      recs[:first_title] = first['fields'].select{|h| h.include? "245"}[0]["245"]["subfields"].select{|s| s.include? "a"}[0]["a"]
    rescue
      recs[:first_title] = ''
    end
    begin
      recs[:second_title] = second['fields'].select{|h| h.include? "245"}[0]["245"]["subfields"].select{|s| s.include? "a"}[0]["a"]
    rescue
      recs[:second_title] = ''
    end


    erb :compare, :locals => {:pair_id=>pair_id, :recs=>recs }
    #erb :compare
  end

  post '/compare/:pair_id' do |pi| #we'll use the form pair_id anyway
    #todo: validation
    @@add_review.execute(params[:pair_id],
                        params[:relationship],
                        params[:note],
                        session['user_name'])
    @@update_pair.execute(params[:pair_id])  
    redirect to('/compare')
  end
    
  get '/reviews/:pair_id' do |pi|
    "Reviews of this pair"
  end
 
  get %r{/reviews([^/]*)} do
    "oops: #{params[:captures].first}"
    limit_start = if params[:captures].first == '' then 0 else params[:captures].first end

    erb :reviews, :locals => {:limit_start=>limit_start, :get_pairs=>@@get_pairs}
    #@@get_pairs.enumerate(limit_start) do | row | 
      
    
  end

  get '/record/:doc_id' do | doc_id |
    return get_source_rec( doc_id )
  end


  def get_next_pair 
    count_sql = "SELECT id, first_id, second_id FROM mr_pairs ORDER BY review_count ASC LIMIT 1"
    @@conn.query(count_sql) do |r|
      return r
    end
  end

  def get_source_rec( doc_id )
    @@get_rec.enumerate(doc_id) do | row | #should just be one, unless I did something stupid
      fname = row[:file_path]
      record_id = row[:record_id] #should be line number
     
      line = `head -#{record_id} #{fname} | tail -1`
      #return JSON.parse(line)  
      line = line.split("\n")[0].chomp
      return line
    end
  end

  def get_recs(first_id, second_id)
    recs = { first: get_source_rec( first_id ),
             second: get_source_rec( second_id ) }
    return recs
  end

  run! if app_file == $0
end
