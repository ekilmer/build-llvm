#!/usr/bin/env python3
import sys
import requests
import os
import argparse
import cpuinfo

CPUINFO = cpuinfo.get_cpu_info()

def post_slack_message(url, msg):
    pass

def parse_output_file(rf):
    filedata = ""
    tagfile = os.path.basename(rf)
    tag, ext = os.path.splitext(tagfile)
    
    with open(rf, 'r') as f:
        filedata = f.read()

    for line in filedata.splitlines():
        l, r = line.split(' ')
        if "real" == l:
            return f"{tag}: {r} seconds"
    
    return f"{tag}: could not parse output!"


def get_results_files(basedir):
    files = os.listdir(basedir)
    
    only_times = filter(lambda x: x.endswith('.time'), files)
    full_paths = map( 
            lambda x: os.path.realpath(os.path.join(basedir, x)),
            only_times)
    

    return full_paths

def compose_message(result_files):
    messages = []
    for rf in sorted(result_files):
        messages.append(parse_output_file(rf))

    return "\n".join(messages)

def post_message(hook, msg, tag):
    cpu = ""
    cpu += f"CPU Brand: {CPUINFO['brand_raw']}\n"
    cpu += f"CPU Count: {CPUINFO['count']}\n"
    
    tag = f"Run tag: {tag}\n"

    msg = tag + cpu + msg
    

    r = requests.post(hook, json={"text": msg})
    return r.status_code == 200

if "__main__" == __name__:
    
    parser = argparse.ArgumentParser(description="Report results to Slack")
    parser.add_argument("--slack-hook", type=str, help="Slack webhook to post messages. Can also be specified by the SLACK_HOOK env var")
    parser.add_argument("--tag", type=str, default="Unknown", help="A tag to identify this run")

    msg_hook = os.getenv("SLACK_HOOK")
    args = parser.parse_args()

    if not msg_hook:
        msg_hook = args.slack_hook

    if not msg_hook:
        sys.stderr.write("Please specify a slack hook via --slack-hook or SLACK_HOOK env var\n")
        parser.print_help()
        sys.exit(1)

    run_tag = args.tag

    sys.stdout.write(f"Slack hook URL: [{msg_hook}]\n")
    sys.stdout.write("Gathering results files...\n")

    mydir = os.path.dirname(os.path.realpath(__file__))
    results_dir = os.path.join(mydir, "results")


    results_files = get_results_files(results_dir)
    result_msg = compose_message(results_files)
    sys.stdout.write(result_msg)
    sys.stdout.write("\n")
    post_message(msg_hook, result_msg, run_tag)
    
    
