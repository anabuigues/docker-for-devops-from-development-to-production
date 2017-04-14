import logging

from flask import Blueprint, Flask, render_template, redirect, request, url_for
from flask_sqlalchemy import SQLAlchemy
from flask_redis import FlaskRedis
from redis import StrictRedis
from sqlalchemy.sql.expression import func


stream_handler = logging.StreamHandler()
stream_handler.setLevel(logging.INFO)

db = SQLAlchemy()
redis_store = FlaskRedis.from_custom_provider(StrictRedis)

page = Blueprint('page', __name__)


def create_app():
    """
    Create a Flask application using the app factory pattern.

    :return: Flask app
    """
    app = Flask(__name__, instance_relative_config=True)

    app.config.from_object('config.settings')
    app.config.from_pyfile('settings.py', silent=True)

    db.init_app(app)
    redis_store.init_app(app)

    app.register_blueprint(page)
    app.logger.addHandler(stream_handler)

    return app


@page.route('/')
def index():
    """
    Render the home page where visitors can feed Moby Dock.

    :return: Flask response
    """
    if request.args.get('feed'):
        random_message = db.session.query(Feedback).order_by(func.random()).limit(1).scalar().message
        feed_count = redis_store.incr('feed_count')
    else:
        random_message = ''
        feed_count = redis_store.get('feed_count')
        if feed_count is None:
            feed_count = 0

    return render_template('layout.html', message=random_message, feed_count=feed_count)


@page.route('/seed')
def seed():
    """
    Reset the database and seed it with a few messages.

    :return: Flask redirect
    """
    db.drop_all()
    db.create_all()

    messages = [
        "Thanks good sir. I'm feeling quite healthy!",
        'Thanks for the meal buddy.',
        "Please stop feeding me. I'm getting huge!"
    ]

    for message in messages:
        feedback = Feedback(message=message)
        db.session.add(feedback)
        db.session.commit()

    return redirect(url_for('page.index'))


class Feedback(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    message = db.Column(db.Text())
