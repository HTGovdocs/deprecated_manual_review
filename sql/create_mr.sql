use ht_repository;

/*-- Drop existing tables.
--drop table if exists manual_reviews;
--drop table if exists mr_pairs;*/

create table mr_pairs (
  id        INT          not null auto_increment,
  first_id  INT          not null,
  second_id INT          not null,
  relationship VARCHAR(50)  not null,
  score DOUBLE not null,
  review_count INT not null DEFAULT 0,
  primary key (id),
  unique key pair (first_id, second_id)
);

create table manual_reviews (
  id        INT         not null auto_increment,
  pair_id   INT         not null,
  relationship VARCHAR(50) not null,
  note TEXT not null DEFAULT '',
  reviewer VARCHAR(255) not null,
  ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  primary key (id),
  foreign key (pair_id) references mr_pairs(id)
);


