require 'sinatra'
require 'sinatra/base'
require 'json'
require 'htph'
require 'dotenv'
Dotenv.load()
require 'erb'
require 'torquebox'


class MrApp < Sinatra::Base

  use TorqueBox::Session::ServletStore, {
    :key => 'sinatra_sessions',
    :domain => 'hathitrust.org',
    :path => '/recordcomp',
    :httponly => true,
  }


  before do
    @@jdbc = HTPH::Hathijdbc::Jdbc.new();
    @@conn = @@jdbc.get_conn();
    if env['PATH_INFO'] !~ /login/ and !session['user_name'] 
      redirect 'recordcomp/login'
    end
  end

   @@get_rec_sql = "SELECT s.source, s.file_path FROM hathi_gd hg 
                      LEFT JOIN gd_source_recs s ON s.file_input_id = hg.file_id AND s.line_number = hg.lineno
                     WHERE hg.id = ? LIMIT 1"
   @@get_pair_sql = "SELECT id, first_id, second_id FROM mr_pairs WHERE id = ? LIMIT 1"

  @@add_review_sql = "INSERT INTO manual_reviews (pair_id, relationship, note, 
                                                  first_gov_doc, second_gov_doc, reviewer)
                      VALUES (?, ?, ?, ?, ?, ?)"
  
  @@update_pair_sql = "UPDATE mr_pairs SET review_count = review_count + 1 
                      WHERE id = ?"

  @@get_pairs_sql = "SELECT * FROM mr_pairs WHERE review_count > 0 LIMIT ?, 100"

  @@get_reviews_sql = "SELECT * from manual_reviews WHERE pair_id = ?"

  @@report_sql = "SELECT mr.*, mp.score FROM manual_reviews mr
                  LEFT JOIN mr_pairs mp ON mr.pair_id = mp.id
                  WHERE DATE_SUB(CURDATE(), INTERVAL 7 DAY) <= ts
                  ORDER BY ts ASC"

  get '/login' do
    erb :login, :locals => {:uname=>session['user_name']} 
  end

  post '/login' do
    open('.users').each do | line |
      u, pw = line.chomp.split(':')
      if params[:name].downcase == u and params[:password].downcase == pw
        session['user_name'] = params[:name]
        redirect 'recordcomp/review'
      end
    end
    #else
    redirect 'recordcomp/login'
  end

  get '/' do
    redirect 'recordcomp/reviews'
    "Manual review of government documents."
  end

  get '/review' do
    pair = get_next_pair
    redirect 'recordcomp/review/'+pair.get_object('id').to_s 
  end

  get '/review/:pair_id' do |pair_id|
    recs = {}
    @@conn.prepared_select(@@get_pair_sql, [pair_id]) do | pair |
      first_id = pair.get_object('first_id')
      second_id = pair.get_object('second_id')
      STDERR.puts 'pair: '+first_id.to_s+', '+second_id.to_s
      recs = get_recs( first_id, second_id )
    end

    erb :review, :locals => {:pair_id=>pair_id, :recs=>recs, :uname=>session['user_name'] }
  end

  post '/review/:pair_id' do |pi| #we'll use the form pair_id anyway
    valid_relationships = ['Unknown', 'Duplicates', 'Duplicates, different media', 'Related', 'Not Related'] 
    unless valid_relationships.include? params[:relationship] #and session['user_name'] != ''
      redirect 'recordcomp/review/'+pi
    end
    first_gov_doc = if params[:first_gov_doc] then 1 else 0 end
    second_gov_doc = if params[:second_gov_doc] then 1 else 0 end
    @@conn.prepared_update(@@add_review_sql, 
                            [params[:pair_id],
                            params[:relationship],
                            params[:note],
                            first_gov_doc,
                            second_gov_doc,
                            session['user_name']])
    @@conn.prepared_update(@@update_pair_sql, [params[:pair_id]])  
    redirect 'recordcomp/review'
  end
    
  get '/reviews/:pair_id' do |pair_id|
    recs = {}
    @@conn.prepared_select(@@get_pair_sql, [pair_id]) do | pair |
      recs = get_recs( pair.get_object('first_id'), pair.get_object('second_id') )
    end
    reviews = []
    @@conn.prepared_select(@@get_reviews_sql, [pair_id]) do | rev |
      reviews << {:relationship=>rev.get_object('relationship'),
                  :note=>rev.get_object('note'),
                  :reviewer=>rev.get_object('reviewer')
                 }
    end
    
    erb :review_of_reviews, :locals => {:reviews=>reviews, 
                                        :pair_id=>pair_id, :recs=>recs }
  end
 
  get '/reviews' do
    limit_start = if params[:start] then params[:start] else 0 end
    pairs = []
    @@conn.prepared_select(@@get_pairs_sql, [limit_start.to_i]) do | pair |
      pairs << {:id=>pair.get_object('id'),
                :review_count=>pair.get_object('review_count'),
                :score=>pair.get_object('score')
               }
    end
    erb :reviews, :locals => {:limit_start=>limit_start, 
                              :pairs=>pairs}
  end

  get '/report' do
    current_date = Time.now.strftime("%Y-%m-%d")
    reviews = []
    @@conn.prepared_select(@@report_sql) do | rev |
      reviews << {:id=>rev.get_object('id'),
                  :pair_id=>rev.get_object('pair_id'),
                  :relationship=>rev.get_object('relationship'),
                  :reviewer=>rev.get_object('reviewer'),
                  :note=>rev.get_object('note'),
                  :time_stamp=>rev.get_object('ts'),
                  :score=>rev.get_object('score')
                 }
    end
    erb :report, :locals => {:current_date=>current_date,
                             :reviews=>reviews}
  end

  get '/record/:doc_id' do | doc_id |
    return get_source_rec( doc_id )
  end

  #stupid and simple
  def extract_field_strs( rec, field )
    begin
#      return rec['fields'].select{|h| h.include? field}[0][field]["subfields"].collect{|s| s.values }.flatten.join(' ')
      return rec['fields'].select{|h| h.include? field}.collect{|f| f[field]['subfields'].collect{|sf| sf.values[0]}.join(' ')}
      #return rec['fields'].select{|h| h.include? field}.collect{|f| f["subfields"].collect{|s| s.values }}.flatten.join(' ')
    rescue
      return []
    end
  end
 
  def get_next_pair 
    #get number of mr_pairs
    num_pairs = 0 
    num_pairs_sql = "SELECT count(*) as num_pairs from mr_pairs"
    @@conn.prepared_select(num_pairs_sql) do |r|
      num_pairs = r.get_object('num_pairs')
    end
    
    #originally this ensured we were getting a record with the lowest review_count. 
    #With 3m pairs, it's more important that we get a random record
    #count_sql = "SELECT id, first_id, second_id FROM mr_pairs ORDER BY review_count ASC LIMIT 1"
    rand_num = rand(num_pairs)
    rand_sql = "SELECT id, first_id, second_id FROM mr_pairs LIMIT ?,1"
    @@conn.prepared_select(rand_sql, [rand_num]) do |r|
      return r
    end
  end

  def get_source_rec( doc_id )
    line = '' 

    @@conn.prepared_select(@@get_rec_sql, [doc_id]) do | row | #should just be one, unless I did something stupid
      line = row.get_object('source').to_s
    end
    if line == '' then line = '["source_missing"]' end
    return JSON.parse(line)
  end

  def get_recs(first_id, second_id)
    recs = { first: get_source_rec( first_id ),
             second: get_source_rec( second_id ) }
    return recs
  end


  run! if app_file == $0
end
