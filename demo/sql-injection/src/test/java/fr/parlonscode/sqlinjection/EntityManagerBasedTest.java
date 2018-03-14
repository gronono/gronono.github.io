package fr.parlonscode.sqlinjection;

import java.util.List;

import org.junit.Assert;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;

@RunWith(SpringRunner.class)
@SpringBootTest
public class EntityManagerBasedTest {

	@Autowired
	private EntityManagerBased emb;
	
	@Test
	public void testBindParamsQuery() {
		// Non injection
		List<Person> result = emb.bindParamsQuery("dsyer");
		Assert.assertEquals(1, result.size());
		Assert.assertEquals("dsyer", result.get(0).getName());
		
		// Test injection
		result = emb.bindParamsQuery("dsyer or 1=1");
		Assert.assertEquals(0, result.size());		
	}

	@Test
	public void testConcatQuery() {
		// Non injection
		List<Person> result = emb.concatQuery("dsyer");
		Assert.assertEquals(1, result.size());
		Assert.assertEquals("dsyer", result.get(0).getName());
		
		// Test injection
		result = emb.concatQuery("dsyer' or '1'='1");
		Assert.assertEquals(4, result.size());
	}

}
