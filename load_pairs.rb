#takes pairs from a text file (output from duplicate detection?) and 
#puts them in the mr_pairs table for review
require 'htph'
require 'pp'

db     = HTPH::Hathidb::Db.new();
@conn  = db.get_conn();

@insert_pair_sql = "INSERT INTO mr_pairs (first_id, second_id, relationship) 
                    VALUES(?,?,?) ON DUPLICATE KEY UPDATE relationship=?"
@insert_pair = @conn.prepare(@insert_pair_sql)
open(ARGV[0]).each do |line|
  rel, gd_id_list = line.chomp.split(/\t/)
  gd_ids = gd_id_list.split(/,/)
  if gd_ids.count == 1
    next
  end 
  #pairwise comparisons
  gd_ids.combination(2).each do | pair |
    @insert_pair.execute(pair[0], pair[1], rel, rel)
  end
end
