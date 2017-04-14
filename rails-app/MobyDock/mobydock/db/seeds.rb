# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)
messages = [
  "Thanks good sir. I'm feeling quite healthy!",
  'Thanks for the meal buddy.',
  "Please stop feeding me. I'm getting huge!"
]

messages.each do |message|
  feedback = Feedback.create(message: message)
  feedback.save!
end
