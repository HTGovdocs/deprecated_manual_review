Manual Review
==========

A stupidly simple Sinatra app for manual review of Govdoc records. 

Setup
-------

Clone with:

    git clone https://github.com/HTGovdocs/manual_review.git

Install (in root dir of cloned project) with bundle:

    bundle install --path .bundle

After bundle install, create a .env file with the following:

    db_driver = xx
    db_url    = xx
    db_user   = xx
    db_pw     = xx
    db_host   = xx
    db_name   = xx
    db_port   = xx

If missing, set up the database tables in /sql/create_mr.sql 

Authorized users should have username:password pair put into a .users file. 


Explanation
-----------

Reviews are performed on pairs of GovDoc records. The pairs that should be reviewed can be added to the mr_pairs table with load_pairs.rb. See the test data in the data directory for sample input. 

Care should be taken to transfer GovDoc record ids from hathi_gd to the hathi_gd_static table in such a way that existing records are not disturbed. 

