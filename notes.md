How to build this site

I have cloned the repo in WSL2
You need to install Ruby and the [Jekyll packages](https://jekyllrb.com/docs/installation/windows/)

`bundle install`

To run locally `bundle exec jekyll serve`

to preview posts that have a future date use the following `bundle exec jekyll serve --future` 

Need to install the thor template first too...

`thor install jekyll_post.thor` , give it a name of "jp"

Have added a thor file to allow the creation of new posts using `thor jekyll_post:new this is a test post` (https://gist.github.com/ichadhr/0b4e35174c7e90c0b31b)

