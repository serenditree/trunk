#!/usr/bin/env python3

import os
from datetime import datetime, timedelta, timezone

import requests


class Retention(object):
    def __init__(self):
        self.snapshots = os.getenv('SNAPSHOT_REPOSITORY')
        self.snapshot_time_format = '%Y-%m-%dT%H:%M:%S.%fZ'
        self.snapshot_retention = 7

    def apply(self):
        snapshots = requests.get(f'{self.snapshots}/_all').json()['snapshots']
        cutoff = datetime.now(timezone.utc) - timedelta(days=self.snapshot_retention)
        count = len(snapshots)
        print(f'Available snapshots: {count}')

        for snapshot in snapshots:
            created = datetime.strptime(snapshot['start_time'], self.snapshot_time_format).astimezone(timezone.utc)
            snapshot_name = snapshot['snapshot']
            if count > 1 and created < cutoff:
                response = requests.delete(f'{self.snapshots}/{snapshot_name}')
                if response.ok and response.json()['acknowledged']:
                    print(f'Deleted snapshot {snapshot_name}')
                    count -= 1
                else:
                    print(f'Could not delete snapshot {snapshot_name}: {response.reason}')
            else:
                print(f'Kept snapshot {snapshot_name}')


if __name__ == '__main__':
    retention = Retention()
    retention.apply()
