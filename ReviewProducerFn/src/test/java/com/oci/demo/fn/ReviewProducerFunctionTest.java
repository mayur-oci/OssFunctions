package com.oci.demo.fn;

import com.fnproject.fn.testing.FnHttpEventBuilder;
import com.fnproject.fn.testing.FnResult;
import com.fnproject.fn.testing.FnTestingRule;
import org.junit.Ignore;
import org.junit.Rule;
import org.junit.Test;

import static org.junit.Assert.assertTrue;

public class ReviewProducerFunctionTest {

    @Rule
    public final FnTestingRule testing = FnTestingRule.createDefault();

    @Ignore
    @Test
    public void test() {
        FnHttpEventBuilder fnHttpEventBuilder = new FnHttpEventBuilder();

        testing.givenEvent().withBody(getReviewJson()).enqueue();

        testing.thenRun(OssProducer.class, "handleRequest");

        FnResult result = testing.getOnlyResult();
        System.out.println("In Junit Test: Result from function call: " + result.getBodyAsString());
        assertTrue(result.getBodyAsString().equals("true"));
    }

    private String getReviewJson() {
        return "{\n" +
                "    \"reviewId\": \"REV_100\",\n" +
                "    \"time\": 200010000000000,\n" +
                "    \"productId\": \"PRODUCT_100\",\n" +
                "    \"reviewContent\": \"review content\"\n" +
                "}";
    }


}