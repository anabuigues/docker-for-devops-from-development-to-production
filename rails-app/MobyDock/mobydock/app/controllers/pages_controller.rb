class PagesController < ApplicationController
  def home
  	if params[:feed].present?
  		@message = Feedback.order('RANDOM()').limit(1).first.message
	    @feed_count = cache_increment('feed_count')
  	else
  		@message = ''
  		@feed_count = Rails.cache.fetch('feed_count') { 0 }
  	end
  end

  private

  def cache_increment(key, amount = 1)
    if (value = Rails.cache.read(key)).nil?
      Rails.cache.write(key, (value = amount))
    else
      Rails.cache.write(key, (value = value + amount))
    end

    return value
  end
end
