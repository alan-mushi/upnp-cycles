#!./bin/python3
from flask import Flask, request, make_response, jsonify
from flask_limiter import Limiter
import json


def get_api_key():
    return request.args.get('key', 'default')


app = Flask('mock_api')
limiter = Limiter(app, key_func=get_api_key, default_limits=["1 per second", "2 per minute"])


@app.route('/api-info', methods=['GET'])
@limiter.limit("1 per second")
def api_info():
    return {"scan_credits": 100, "usage_limits": {"scan_credits": 100, "query_credits": 100, "monitored_ips": 16}, "plan": "dev", "https": False, "unlocked": True, "query_credits": 100, "monitored_ips": None, "unlocked_left": 100, "telnet": False}


@app.route('/shodan/host/search', methods=['GET'])
#@limiter.limit("1 per second")
def host_search():
    page = int(request.args.get('page', 1))

    page = page if page <= 3 else '_end'

    with open('response{}.json'.format(page), 'r') as f:
        return json.load(f)


@app.errorhandler(429)
def ratelimit_handler(e):
    return make_response(jsonify(error="Insufficient query credits, please" \
    "upgrade your API plan or wait for the monthly limit to reset"), 401)
