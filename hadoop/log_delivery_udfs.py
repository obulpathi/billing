# Copyright (c) 2015 Rackspace, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# log_delivery_udfs.py


@outputSchema("chararray")
def relative_uri(uri):
    if uri:
        string = uri.tostring()
        tokens = string.split('/')
        parts = tokens[2:]
        relative_uri = '/'.join(token for token in parts)
        return '/' + relative_uri
    else:
        return uri

@outputSchema("chararray")
def day_month_year(date):
    if date:
        string = date.tostring()
        tokens = string.split('-')
        start = tokens[-1:]
        end = tokens[:1]
        middle = tokens[1:-1]
        return '/'.join(start + middle + end)
    else:
        return date