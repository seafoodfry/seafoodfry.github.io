FROM ruby:3.4.3

RUN gem install jekyll jekyll-gist jekyll-sitemap jekyll-seo-tag jekyll-paginate webrick
COPY . /app

WORKDIR /app
ENTRYPOINT ["jekyll", "serve", "--livereload", "--host", "0.0.0.0"]
