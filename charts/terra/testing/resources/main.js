import {Httpx} from 'https://jslib.k6.io/httpx/0.1.0/index.js';
import {check, fail, group, sleep} from 'k6';
import faker from 'k6/x/faker';
import {Rate} from 'k6/metrics';
import {randomOption, randomSeed, randomTiles, randomUser, SeedFilter, ST_HEADERS, ST_SORTING} from './data.js';

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// INIT
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
const userClient = new Httpx({
    baseURL: `http://${__ENV.BRANCH_USER}/api/v1/user`,
    timeout: 4000
});

const seedClient = new Httpx({
    baseURL: `http://${__ENV.BRANCH_SEED}/api/v1/seed`,
    timeout: 2000
});

const pollClient = new Httpx({
    baseURL: `http://${__ENV.BRANCH_POLL}/api/v1/poll`,
    timeout: 2000
});

const mapClient = new Httpx({
    baseURL: `http://${__ENV.ROOT_MAP}/data/v3`,
    timeout: 2000
});

const emptyTiles = new Rate('empty_tiles');

const SIGN_UP_EXPECTED_STATUS = 201;
const SIGN_UP_MAX_RETRIES = 2;

export const options = {
    stages: [
        {target: 10, duration: '30s'},
        {target: 50, duration: '1m'},
        {target: 10, duration: '30s'},
    ],
    thresholds: {
        http_req_failed: ['rate < 0.01'],
        http_req_duration: ['p(95) < 400'],
        empty_tiles: ['rate < 0.25']
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// UTILS
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function statusCheck(response, status) {
    if (response.status !== status) {
        console.error(status)
        console.error(response);
    }
    check(response, {'OK': r => r.status === status});
}

function signUp(user) {
    let signUpResponse = userClient.post('/sign-up', null, user);
    let retryCount = 0;

    while (signUpResponse.status !== SIGN_UP_EXPECTED_STATUS && retryCount++ < SIGN_UP_MAX_RETRIES) {
        console.error(`Sign up failed with status [${signUpResponse.status}]. Retrying...`);
        sleep(1);
        signUpResponse = userClient.post('/sign-up', null, user);
    }

    return signUpResponse;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// SETUP
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
export function setup() {
    const user = randomUser();
    const signUpResponse = signUp(user);

    if (signUpResponse.status !== SIGN_UP_EXPECTED_STATUS) {
        fail(`Setup failed with status [${signUpResponse.status}]. Aborting...`);
    }

    const userId = signUpResponse.headers[ST_HEADERS.id];
    const username = user.headers[ST_HEADERS.username];
    const password = user.headers[ST_HEADERS.password];
    console.log(`Created user [${username}] with ID [${userId}] and password [${password}]`);

    return {
        authorization: signUpResponse.headers['Authorization'],
        userId: userId,
        username: username,
        password: password
    };
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// TEST
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
export default function (data) {
    userClient.addHeader('Authorization', data.authorization);
    seedClient.addHeader('Authorization', data.authorization);
    pollClient.addHeader('Authorization', data.authorization);
    const groupTag = 'name';
    let tag;
    let seedId;
    let hasPoll;
    let pollId;
    let optionId;

    tag = '/seed/create';
    seedClient.addTag(groupTag, tag);
    group(tag, () => {
        const createSeedResponse = seedClient.post('/create', randomSeed());
        statusCheck(createSeedResponse, 201);
        seedId = createSeedResponse.json('id');
        hasPoll = createSeedResponse.json('poll');
    });
    sleep(faker.numbers.float32Range(0, 1));

    tag = '/seed/{id}';
    seedClient.addTag(groupTag, tag);
    group(tag, () => {
        const seedGetResponse = seedClient.get(`/${seedId}`);
        statusCheck(seedGetResponse, 200);
    });

    if (hasPoll) {
        tag = '/poll/seed/{id}';
        pollClient.addTag(groupTag, tag);
        group(tag, () => {
            const pollBySeedResponse = pollClient.get(`/seed/${seedId}`);
            statusCheck(pollBySeedResponse, 200);
            const option = randomOption(pollBySeedResponse);
            pollId = pollBySeedResponse.json(`${option.poll}.id`);
            optionId = pollBySeedResponse.json(`${option.poll}.options.${option.option}.id`);
        });

        tag = '/poll/vote/{pollId}/{optionId}';
        pollClient.addTag(groupTag, tag);
        group(tag, () => {
            const voteResponse = pollClient.get(`/vote/${pollId}/${optionId}`);
            statusCheck(voteResponse, 200);
        });
    }

    tag = '/seed/auth/{userId}/{entityId}/{action}';
    seedClient.addTag(groupTag, tag);
    group(tag, () => {
        const action = faker.strings.randomString(['water', 'nubit', 'prune']);
        const seedAuthResponse = seedClient.get(`/auth/${data.userId}/${seedId}/${action}`);
        statusCheck(seedAuthResponse, 200);
    });

    tag = '/seed/retrieve';
    seedClient.addTag(groupTag, tag);
    group(tag, () => {
        const seedRetrieveByBoundsByWaterResponse = seedClient.post(
            '/retrieve',
            new SeedFilter()
                .setBounds()
                .setSort(ST_SORTING.water)
                .build()
        );
        statusCheck(seedRetrieveByBoundsByWaterResponse, 200);
        const seedRetrieveByBoundsByDateResponse = seedClient.post(
            '/retrieve',
            new SeedFilter()
                .setBounds()
                .setSort(ST_SORTING.date)
                .build()
        );
        statusCheck(seedRetrieveByBoundsByDateResponse, 200);
    });

    tag = '/map/retrieve';
    mapClient.addTag(groupTag, tag);
    group(tag, () => {
        const retrieveMapResponses = mapClient.batch(randomTiles(3));
        for (const response of retrieveMapResponses) {
            check(response, {
                'OK': (r) => {
                    return r.status === 204 ||
                        r.status === 200 &&
                        r.headers?.['Content-Type']?.includes('application/x-protobuf');
                }
            });
            emptyTiles.add(response.status === 204);
        }
    });
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// TEARDOWN
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
export function teardown(data) {
    userClient.addHeader('Authorization', data.authorization);
    const deleteResponse = userClient.delete(`/${data.userId}/true`);

    if (deleteResponse.status === 200) {
        console.log(`Removed all data for user [${data.username}] with ID [${data.userId}]`);
    } else {
        console.error(deleteResponse);
    }
}
